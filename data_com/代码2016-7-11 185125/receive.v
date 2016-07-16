//==================================================================================================
//  Filename      : receive.v
//  Created On    : 2016-06-14 08:40:59
//  Last Modified : 2016-07-11 17:25:57
//  Revision      :
//  Author        : PanShen
//  Email         : pan_shen@foxmail.com
//
//  Description   :
//
//
//==================================================================================================

`timescale 1ns/1ps

// `define  DEBUG_MODE

`ifdef DEBUG_MODE

module receive (
    channel,    //通道标号
    sclr,
    ce,
    mode,
    ch_clk,
    clk,

    hblank_in,
    vblank_in,
    active_video_in,

    row_start,
    row_end,
    col_start,
    col_end,
    //to data save
    wr_addr1,
    wr_addr2,
    pp_flagw,
    pp_flagr,
    effect_reigon,
    //to send
    send_start,//receive --> send通知send.v开始发送数据了
    col_max,   //receive --> send,告知send开始那段的宽度
    row_max,
    col_cnt,
    row_cnt,
    hblank_low ///receive --> send,告知send测试模式有效数据宽度
);

`else

module receive (
    channel,    //通道标号
    sclr,
    ce,
    mode,
    ch_clk,
    clk,

    hblank_in,
    vblank_in,
    active_video_in,

    row_start,
    row_end,
    col_start,
    col_end,
    //to data save
    wr_addr1,
    wr_addr2,
    pp_flagw,
    pp_flagr,
    effect_reigon,
    //to send
    send_start,//receive --> send通知send.v开始发送数据了
    col_max,   //receive --> send,告知send开始那段的宽度
    row_max,
    hblank_low ///receive --> send,告知send测试模式有效数据宽度
);

`endif

parameter CHANNEL_IN_NUM   = 4;     //输入数据块数量2^6 == 63
parameter CHANNEL_OUT_NUM  = 1;     //输出数据块数量
parameter VIDEO_DATA_WIDTH = 18;    //视频数据信号宽度
parameter RAM_DEPTH        = 100;   //行缓存ram深度
parameter TIMING_CNT_WIDTH = 10;    //行、列计数器信号宽度
parameter OVERLAP_WIDTH    = 2;     //输出数据块交叠量
parameter TOP_BOTTOM_SEL   = 1'd1;  //输入数据块由上、下部分组成标识
parameter HEAD_DIRECTION   = 1'd0;  //抽头方向0全左,1全右,2对半分
parameter FRAME_RAM_EN     = 1'd0;  //帧缓存使能
//一个发送块包含多少个输入块，输出计数器是输入的多少倍
localparam TIMES           = CHANNEL_IN_NUM/CHANNEL_OUT_NUM;
//根据RAM深度生成，RAM操作地址宽度
localparam ADDR_WIDTH      = clogb2(RAM_DEPTH-1);//addra,addrb width
localparam OVERLAP_W       = clogb2(OVERLAP_WIDTH+1);
`ifdef  DEBUG_MODE

output [TIMING_CNT_WIDTH-1'b1:0]    col_cnt;        //send <-- receive
output [TIMING_CNT_WIDTH-1'b1:0]    row_cnt;        //send <-- receive，测试模式用

wire                                hbi_high;

`endif

input [5:0]                         channel;//integer
input                               sclr;
input                               ce;
input                               mode;
input                               ch_clk;
input                               clk;    //faster

input                               hblank_in;
input                               vblank_in;
input                               active_video_in;

//以下四个参数结合结合行列计数器确定有效数据区域
input [TIMING_CNT_WIDTH-1'b1:0]     row_start;
input [TIMING_CNT_WIDTH-1'b1:0]     row_end;
input [TIMING_CNT_WIDTH-1'b1:0]     col_start;
input [TIMING_CNT_WIDTH-1'b1:0]     col_end;
//接收通知发送模块开始工作
output                              send_start;     //send <-- receive
//hblank_in一行最大值，同于使hblank_out保持一样的一个发送周期的时间
output [TIMING_CNT_WIDTH-1'b1:0]    col_max;        //send <-- receive
output [TIMING_CNT_WIDTH-1'b1:0]    row_max;        //send <-- receive，测试模式用
output [TIMING_CNT_WIDTH-1'b1:0]    hblank_low;     //send <-- receive
output [ADDR_WIDTH-1'b1:0]          wr_addr1;        //接收指针，ram0使用
output [ADDR_WIDTH-1'b1:0]          wr_addr2;       //发送指针，ram1使用
output                              pp_flagw;        //写乒乓操作
output                              pp_flagr;       //读乒乓操作
output                              effect_reigon;  //有效区
//other reg
reg    [TIMING_CNT_WIDTH-1'b1:0]    row_cnt;        //列计数器
reg    [TIMING_CNT_WIDTH-1'b1:0]    col_cnt;        //行计数器
reg    [TIMING_CNT_WIDTH-1'b1:0]    col_max;        //hblank_in一行最大值，包括高电平区
reg    [TIMING_CNT_WIDTH-1'b1:0]    row_max;        //hblank_in有效低电平行数最大值
reg    [TIMING_CNT_WIDTH-1'b1:0]    hblank_low;     //active_video_in低电平区域长度，测试模式用

reg    [ADDR_WIDTH-1'b1:0]          wr_addr1;        //接收指针，ram0使用
reg    [ADDR_WIDTH-1'b1:0]          wr_addr2;       //发送指针，ram1使用
reg    [OVERLAP_W-1:0]              row_save_cnt1;  //指示已经存了几行数据
reg    [OVERLAP_W-1:0]              row_save_cnt2;  //指示已经存了几行数据
reg                                 send_start;     //告诉send开始发数据
reg                                 send_once;      //只生成一次send_start
reg                                 col_cnt_en;     //col_cnt使能，为0 代表发送快数据发送完成
reg    [OVERLAP_W-1:0]              overlap_cnt;    //最后产生多少pp_flag
reg                                 active_sync;    //向后延时
reg                                 hblank_sync;
//wire -> reg
reg   [ADDR_WIDTH-1'b1:0]           effect_width;   //有效宽度
reg                                 effect_reigon;

wire                                active_neg;
wire                                hblank_neg;
wire                                hblank_pos;
// wire   [ADDR_WIDTH-1'b1:0]          effect_width;   //有效宽度
reg    [OVERLAP_W-1:0]              row_save;       //缓存多少行数据
reg                                 effect_row;     //列有效了
//state reg
reg    [2:0]                        cur_state;
reg    [2:0]                        next_state;


reg                                 pp_flagw;       //乒乓缓存标志位，0:选择ram0, 1:选择ram1
reg                                 pp_flagr;       //乒乓缓存标志位，0:选择ram0, 1:选择ram1
reg                                 reverse_en;     //存储方向是否反向,高有效
reg                                 wait_;          //交叠区返回转折点时，pp_flag停顿一个接收周期，,正常模式！
reg                                 once;
//state machine state data
localparam   IDLE          = 3'b001;                //空闲等待
localparam   REC           = 3'b010;                //接收数据状态
localparam   NXT           = 3'b100;                //换行


always @(posedge ch_clk) begin
    if(sclr) begin
        active_sync <= 0;
    end else if(ce) begin
        active_sync <= active_video_in;
    end
end
//negedge of active_video_i,for pp_flag use for modelsim
// assign active_neg = (!active_sync[0] && active_sync[1]) ? 1'b1:1'b0;
assign active_neg = (!active_video_in && active_sync) ? 1'b1:1'b0;

always @(posedge ch_clk) begin
    if(sclr) begin
        hblank_sync <= 1;
    end else if(ce) begin
        hblank_sync <= hblank_in;
    end
end

assign hblank_neg = (!hblank_in && hblank_sync) ? 1'b1:1'b0;
assign hblank_pos = (hblank_in && !hblank_sync) ? 1'b1:1'b0;

//state refresh
always@(posedge ch_clk)
begin
    if(sclr)
        cur_state <= IDLE;
    else if(ce)
        cur_state <= next_state;
end

//状态机跳转条件
always@(*)
begin
    if(ce) begin
        case(cur_state)
            IDLE: begin
                //有效数据开始了
                if(active_video_in) begin
                    next_state = REC;
                end else begin
                    next_state = IDLE;
                end
            end
            REC:  begin
                if(!active_video_in) begin
                    //一帧数据收完，vblank_in拉高
                    if(vblank_in)
                        next_state = IDLE;
                    else
                        next_state = NXT;
                end else begin
                    next_state = REC;
                end
            end
            NXT: begin
                //active_video_in拉高，新的一行数据又来了
                // if(active_in_pos) begin//采沿因此会滞后一个周期
                if(active_video_in) begin
                    next_state = REC;
                end else begin
                    next_state = NXT;
                end
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end else begin
        next_state = IDLE;
    end
end


always@(posedge ch_clk)
begin
    if(sclr)begin
        col_cnt_en <= 1'b0;
        overlap_cnt <= 0;
        once <= 1'b1;
    end else if(ce) begin
        if(cur_state == IDLE && next_state == REC) begin
            col_cnt_en <= 1'b1;
            overlap_cnt <= 0;
        //接收期间不会相等,max是col_cnt在接收期间最大值加一，+1是因为发送比接收往后延时一行！
        end else if(col_cnt == col_max -1 && next_state == IDLE && row_cnt > row_end + 1 && mode) begin
            overlap_cnt  <= overlap_cnt + 1'b1;
            //确保交叠行发送完成
            if(TOP_BOTTOM_SEL && !FRAME_RAM_EN && mode) begin//有行交叠&& mode，正常模式！
                if(OVERLAP_WIDTH == overlap_cnt || overlap_cnt == OVERLAP_WIDTH + row_end - row_max ) begin//最后几行
                    col_cnt_en <= 0;//此时发送完成
                    once <= 1'b1;
                end
            end
            else begin //没行交叠，关闭使能
                col_cnt_en <= 0;
                once <= 1'b1;
            end
        //第一个低电平使能，解决多帧问题
        end else if(!hblank_in && once) begin
            col_cnt_en <= 1'b1;
            once <= 0;
        //测试模式立即清零,,row_cnt > row_max + 1最后一个pp——flag
        end else if(next_state == IDLE && !mode && row_cnt > row_max + 1) begin//关早了
            col_cnt_en <= 0;//此时发送的最后一行发送完成！
            once <= 1'b1;
        end
    end
end
//squential logic
//行计数器，行最大值生成
always@(posedge ch_clk)
begin
    if(sclr)begin
        col_cnt <= 0;
        col_max <= {TIMING_CNT_WIDTH{1'b1}};
        hblank_low <= {TIMING_CNT_WIDTH{1'b1}};//初始化一个较大值
    end
    else if(ce) begin
        case(next_state)
            IDLE: begin//不计数，降低功耗//需要计数，由于行交叠要使用pp_flagr
                // col_max <= 0;//清零导致发送端的交叠区卡死在行消隐,pp_flagr
                // hblank_low <= {TIMING_CNT_WIDTH{1'b1}};//初始化一个较大值
                // 此处改变hbl导致发送计数器门限改变，从而状态机门限失灵
                if(hblank_pos  && !vblank_in) begin//!vbi避免最后一个hbipos影响
                    hblank_low <= col_cnt + 1;//输入异常会影响到其值
                end
                //col_cnt_en==0代表，交叠行发送完成
                if(!col_cnt_en) begin
                    col_max <= {TIMING_CNT_WIDTH{1'b1}};
                end

                if(col_cnt == (col_max -1) || hblank_neg) begin
                    col_cnt <= 0;
                end else if(col_cnt_en) begin
                    col_cnt <= col_cnt + 1;
                end else begin
                    col_cnt <= 0;
                end
            end
            REC:begin
                if(cur_state == IDLE) begin
                    col_cnt <= 0;
                    col_max <= col_cnt + 1;//由于col_cnt必须从0开始计数(col_start可能为0)
                end else if(cur_state == NXT) begin
                    col_cnt <= 1'b0;
                end else begin
                    col_cnt <= col_cnt + 1'b1;
                end
            end
            NXT:begin
                // if(cur_state == REC) begin
                //     hblank_low <= col_cnt + 1;//可以提前
                // end
                col_cnt <= col_cnt + 1'b1;
            end
            default:begin
                col_cnt <= 0;
            end
        endcase
     end
end

always@(posedge ch_clk)
begin
    if(sclr)begin
        row_cnt <= 0;
    end
    else if(ce) begin
        //接收到换行或者结束即认为输入了一行 99,effect_width < hblank_low要求不会与下面跳转条件重复
        if((((next_state == NXT || (next_state == IDLE && effect_width < hblank_low)) && cur_state == REC) ||//本块
            //交叠行区域，
           (next_state == IDLE && row_cnt > row_end -1 && col_cnt == effect_width)) && mode) begin//后面继续加，wait需要使用
            row_cnt <= row_cnt + 1'b1;
        //测试模式，需要用row_max判断！
        end else if(((next_state == NXT && cur_state == REC) ||//本块
           (next_state == IDLE && row_cnt > row_max -1 && col_cnt == effect_width)) && !mode) begin//后面继续加，wait需要使用
            row_cnt <= row_cnt + 1'b1;
        //发送结束
        end else if(next_state == IDLE && !col_cnt_en) begin//overlap_cnt还需要使用，暂时不能清零
            row_cnt <= 0;
        end
    end
end

//列计数器最大值，测试模式和hblank_low一起起作用
always@(posedge ch_clk)
begin
    if(sclr)begin
        row_max <= 0;
    end
    else if(ce) begin
        //防止第二帧行计数最大值变小
        if(next_state == REC && cur_state == IDLE) begin
            row_max <=0;
        //next_state == REC,防止后面无效行干扰
        end else if(row_max < row_cnt && next_state == REC) begin//延时更小
            row_max <= row_cnt;
        end
     end
end

//send_start信号生成，通知send模块开始工作
always@(posedge ch_clk)
begin
    if(sclr)begin
        send_start <= 0;
        send_once  <= 1'b1;
    end else if(ce) begin
        //row_cnt == 0 时候，接收第0行就启动发送
        if(next_state == IDLE) begin
            send_once  <= 1'b1;
            send_start <= 0;
        //加active_video_in以防row_start == 0
        // if(effect_reigon) begin//等待effect_col会滞后
        end else if(effect_row && active_video_in && send_once && mode) begin
            send_start <= 1'b1;
            send_once  <= 1'b0;
        end else if(active_video_in && send_once && !mode) begin
            send_start <= 1'b1;
            send_once  <= 1'b0;
        end else if(next_state == NXT) begin
        //产生多了会导致send的col_cnt清零
            send_start <= 0;
        end
    end
end


//乒乓操作写标志位生成
always @(posedge ch_clk) begin
    if(sclr) begin
        pp_flagw <= 1'b1;
    end else if(ce) begin
        //行消隐太长，导致
        if(col_cnt == col_max-4 && col_max > 4 && mode && row_cnt > row_start) begin
            pp_flagw <= ~pp_flagw;
        end else if(active_neg && !mode) begin
            pp_flagw <= ~pp_flagw;
        end else if(next_state == IDLE && !col_cnt_en) begin//每一帧进行一帧重置
            pp_flagw <= 1'b1;
        end
    end
end

//乒乓读操作标志位生成,不能停，直到交叠完成！！
////读RAM乒乓标志
//读地址提前hbo_neg两个clk赋值,
//在整个hbo低电平控制输出数据
always @(posedge ch_clk) begin
    if(sclr) begin
        pp_flagr <= 1'b1;
        wait_ <= 0;
    end else if(ce) begin
        //换行阶段暂停一次变换,pp_flag也影响发送过来的数据
        // if(col_cnt == col_max-1 && col_max >1) begin//影响发送左边填充第一个地址
        if((row_cnt == row_end + 2) && mode) begin
            wait_ <= 1'b1;
        end else begin
            wait_ <= 0;
        end
        //因此行消隐时间不能太短，少于4clk
        //col_max比col_cnt实际最大值大1，而它实际最大值又比hbi下降沿滞后1clk，
        //此外又要提前2clk给地址赋值，所以需要减4！！（至少）
        // if(col_cnt == col_max-4 && !wait_) begin
        //     pp_flagr <= ~pp_flagr;
        // end
        // hbo比hbi整体向后延迟了3clk，它实际最大值又比hbi下降沿滞后1clk
        // if(col_cnt == col_max - 1 && !wait_) begin
        if(col_cnt == col_max - 2 && !wait_) begin
            pp_flagr <= ~pp_flagr;//由于行交叠后面还要继续变化一段时间
        end else if(send_start) begin//每一帧进行一帧重置
            pp_flagr <= 1'b1;
        end
    end
end



//缓存行数
always @(posedge ch_clk) begin
    if(sclr) begin
        //第一次均未使用，目的是为下一次清零准备
        //正常模式，多行缓存
        //当row_start = 0,时，wr_addr1,wr_addr2不需要用到row_save_cnt1,2,不影响写地址
        //而row_start = 1,时，wr_addr1,wr_addr2需要用到row_save_cnt1,2,影响写地址，一开始需要为0
        row_save_cnt1 <= (TOP_BOTTOM_SEL && !FRAME_RAM_EN && mode) ? ((OVERLAP_WIDTH-1)/2): 0;
        row_save_cnt2 <= (TOP_BOTTOM_SEL && !FRAME_RAM_EN && mode) ? ((OVERLAP_WIDTH-1)/2): 0;
    //有效行区间
    end else if(ce) begin
        // 一行数据接收完成！pp_flagw变了，所以下面需要取反
        if(cur_state == REC && next_state == NXT && (row_cnt + 1) >= row_start) begin
            //不存在行交叠,只缓存一行,或者是测试模式
            if((!(TOP_BOTTOM_SEL && !FRAME_RAM_EN && mode)) || (row_start == 0 && row_cnt == 0)) begin
                row_save_cnt1 <= 0;
                row_save_cnt2 <= 0;
            //为第一行数据做准备
            end else if((row_cnt + 1 == row_start) || (row_save_cnt1 == row_save && !pp_flagw)) begin
                row_save_cnt1 <= 0;
            //多行缓存达到目标，接受地址清零
            end else if(row_save_cnt2 == row_save && pp_flagw) begin
                row_save_cnt2 <= 0;
            end else begin
                //乒乓标志决定操作哪一个计数器
                if(!pp_flagw) begin
                    row_save_cnt1 <= row_save_cnt1 +  1;
                end else begin
                    row_save_cnt2 <= row_save_cnt2 +  1;
                end
            end
        end else if(next_state == IDLE) begin
            row_save_cnt1 <= (TOP_BOTTOM_SEL && !FRAME_RAM_EN && mode) ? ((OVERLAP_WIDTH-1)/2): 0;
            row_save_cnt2 <= (TOP_BOTTOM_SEL && !FRAME_RAM_EN && mode) ? ((OVERLAP_WIDTH-1)/2): 0;
        end
    end
end

//存储指针是否逆序递减？
always @(posedge ch_clk) begin
    if(sclr) begin
        reverse_en <= 0;
    end else if(ce) begin
        if(HEAD_DIRECTION==0) begin
            reverse_en <= 0;
        end else if(HEAD_DIRECTION==1) begin
            reverse_en <= 1;
        end else if(HEAD_DIRECTION == 2) begin
            //一行排列
            if(!TOP_BOTTOM_SEL) begin
                if(CHANNEL_IN_NUM == 1) begin//0 !< 0
                    reverse_en <= 0;
                end else if((channel < CHANNEL_IN_NUM/2)) begin
                    reverse_en <= 0;
                end else begin
                    reverse_en <= 1;
                end
            //两行排列
            end else begin
                //左侧
                if(CHANNEL_IN_NUM <= 2) begin
                    reverse_en <= 0;
                end else if((channel < CHANNEL_IN_NUM/4) ||(channel >= (CHANNEL_IN_NUM - CHANNEL_IN_NUM/4))) begin
                    reverse_en <= 0;
                //右侧
                end else if((channel >= CHANNEL_IN_NUM/4) || (channel < (CHANNEL_IN_NUM - CHANNEL_IN_NUM/4))) begin
                    reverse_en <= 1;
                end
            end
        end
    end
end


//计数指针
always @(posedge ch_clk) begin
    if(sclr) begin
        wr_addr1 <= reverse_en ? effect_width-1:0;//确保第一次是从0开始计数
        wr_addr2 <= reverse_en ? effect_width-1:0;//ram1
    //有效行区间
    end else if(ce) begin
        //hblank_in拉高,一行收完，是否达到目标，是否需要清零
        //cur 比 next慢 1clk
        if(next_state == NXT) begin// 一行数据接收完成！cur_state == REC &&
            if(pp_flagw) begin
                wr_addr1 <= reverse_en ? (effect_width*(row_save_cnt1 + 1'b1) - 1'b1):(effect_width*row_save_cnt1);
            end else begin
                wr_addr2 <=  reverse_en ? (effect_width*(row_save_cnt2 + 1'b1) - 1'b1):(effect_width*row_save_cnt2);
            end
        //未接收完，在有效列区间
        end else if(effect_reigon) begin //有时候不能清0
            if(pp_flagw) begin
                wr_addr1 <= reverse_en ? (wr_addr1 - 1'b1):(wr_addr1 + 1'b1);
            end else begin
                wr_addr2 <= reverse_en ? (wr_addr2 - 1'b1):(wr_addr2 + 1'b1);
            end
        end else if(next_state == IDLE) begin//cur_state == REC &&
            wr_addr1 <= reverse_en ? effect_width-1:0;//确保第一次是从0开始计数
            wr_addr2 <= reverse_en ? effect_width-1:0;//ram1
        end
    end
end

always @(posedge ch_clk) begin
    if(sclr) begin
        effect_width  <= 0;
        // effect_reigon <= 0;
        effect_row    <= 0;
        row_save      <= 0;
    end else if(ce) begin
        effect_width  <= mode ? (col_end - col_start + 1'b1):hblank_low;//一行指针最大值
        // effect_reigon <= mode ? (effect_row && effect_col && (next_state == REC)) : active_video_in;//延时

        effect_row    <= (row_cnt >= row_start) && (row_cnt <= row_end);
        row_save      <= (TOP_BOTTOM_SEL && !FRAME_RAM_EN && mode) ? ((OVERLAP_WIDTH-1)/2):1'b0;
    end
end


//有效宽度
// assign effect_width = mode ? (col_end - col_start + 1'b1):hblank_low;//一行指针最大值

//两行排列，缓存失能，设置保存行数
// assign row_save = (TOP_BOTTOM_SEL && !FRAME_RAM_EN && mode) ? ((OVERLAP_WIDTH-1)/2):1'b0;

//行列有效信号生成,active_in_pos是col_cnt等于最大值的时候，但实际上此时col_cnt应该是0
//assign effect_col = (col_cnt >= col_start) && (col_cnt <= col_end);
always @(posedge ch_clk) begin
    if(sclr) begin
        effect_reigon <= 0;
    end else if(ce) begin
        if(mode) begin
            if(col_start > 0) begin
                effect_reigon <= (col_start - 1 <= col_cnt && col_cnt <= col_end &&  effect_row && next_state == REC);//延时
            //最开头的时候，col_max无效没法使用
            end else if(cur_state == IDLE && next_state ==REC) begin//=0
                effect_reigon <= effect_row;
            end else begin
                effect_reigon <= (((col_cnt >= 0 && col_cnt <= col_end) || (col_cnt == col_max-1)) &&
                                    effect_row && (next_state == REC));//延时
            end
        end else begin
            effect_reigon <= active_video_in;
        end
    end
end

// assign effect_row = (row_cnt >= row_start) && (row_cnt <= row_end);
//mode == 1正常模式，加上(next_state == REC)目的是为了防止在col_start == row_start == 0的时候，
//由于对应计数器初值也为0，而导致错误的判断
// assign effect_reigon = mode ? (effect_row && effect_col && (next_state == REC)) : active_video_in;


//  The following function calculates the address width based on specified RAM depth
function integer clogb2;
    input integer depth;
    for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
endfunction


`ifdef  DEBUG_MODE

assign hbi_high = (hblank_low-1) <= col_cnt && col_cnt <= (col_max - 2) && row_cnt > 0 ? 1'b1 : 1'b0;

`endif

endmodule
