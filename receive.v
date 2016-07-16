//=================================================================================================
//  Company       : LVIT Ltd.
//  Filename      : receive.v
//  Description   : 数据接收模块
//  Date          : 2016年7月12日 10:22:46
//  Author        : PanShen
//=================================================================================================

`timescale 1ns/1ps

// `define  DEBUG_MODE

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

`ifdef DEBUG_MODE
    col_cnt,
    row_cnt,
`endif
    hblank_low ///receive --> send,告知send测试模式有效数据宽度
);


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
localparam ADDR_WIDTH      = clogb2(RAM_DEPTH - 1);//addra,addrb width
localparam OVERLAP_W       = clogb2(OVERLAP_WIDTH + 1);

`ifdef  DEBUG_MODE

output [TIMING_CNT_WIDTH-1'b1:0]    col_cnt;        //send <-- receive
output [TIMING_CNT_WIDTH-1'b1:0]    row_cnt;        //send <-- receive，测试模式用

wire                                hbi_high;
wire                                hblank_err;
`endif

input [5:0]                         channel;
input                               sclr;
input                               ce;
input                               mode;
input                               ch_clk;
input                               clk;            //faster than ch_clk

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
output [ADDR_WIDTH-1'b1:0]          wr_addr1;       //接收指针，ram0使用
output [ADDR_WIDTH-1'b1:0]          wr_addr2;       //发送指针，ram1使用
output                              pp_flagw;       //写乒乓操作
output                              pp_flagr;       //读乒乓操作
output                              effect_reigon;  //有效区
//other reg
reg    [TIMING_CNT_WIDTH-1'b1:0]    row_cnt;        //列计数器
reg    [TIMING_CNT_WIDTH-1'b1:0]    col_cnt;        //行计数器
reg    [TIMING_CNT_WIDTH-1'b1:0]    col_max;        //hblank_in一行最大值，包括高电平区
reg    [TIMING_CNT_WIDTH-1'b1:0]    row_max;        //hblank_in有效低电平行数最大值
reg    [TIMING_CNT_WIDTH-1'b1:0]    hblank_low;     //active_video_in低电平区域长度，测试模式用

reg    [ADDR_WIDTH-1'b1:0]          wr_addr1;       //接收指针，ram0使用
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
reg                                 effect_reigon;  //有效区域

wire                                active_neg;
wire                                hblank_neg;
wire                                hblank_pos;
reg    [OVERLAP_W-1:0]              row_save;       //缓存行数
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

//状态更新
always@(posedge ch_clk)
begin
    if(sclr)
        cur_state <= IDLE;
    else if(ce)
        cur_state <= next_state;
end

/*
* 状态机说明
* IDLE: 空闲，等待有效数据
* REC: 数据接收状态
* NXT: 行消隐状态
*/
//状态机切换
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
            REC: begin
                //一行数据收完，消隐或者结束
                if(!active_video_in) begin
                    //vblank_in拉高，一帧数据收完
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
        col_cnt_en  <= 1'b0;
        overlap_cnt <= 0;
        once        <= 1'b1;
    end else if(ce) begin
        //空闲到接收状态，新的一帧数据
        if(cur_state == IDLE && next_state == REC) begin
            col_cnt_en  <= 1'b1;
            overlap_cnt <= 0;
        //一帧末尾，由于发送滞后，发送读去RAM需要使用pp_flagr，因此row_cnt需要计数计数到发送完成
        end else if(col_cnt == col_max -1 && next_state == IDLE && row_cnt > row_end + 1 && mode) begin
            overlap_cnt  <= overlap_cnt + 1'b1;
            //确保交叠行发送完成，出于低功耗考虑，及时关闭使能信号
            if(TOP_BOTTOM_SEL && !FRAME_RAM_EN && mode) begin
                if((OVERLAP_WIDTH == overlap_cnt) ||                          //发送在空闲状态之前未发送交叠行
                  (row_cnt - row_end > OVERLAP_WIDTH) ||                      //发送在空闲状态之前已经发送完成
                  (overlap_cnt == OVERLAP_WIDTH + row_end - row_max)) begin   //发送在空闲状态之前已经发送部分交叠行
                    col_cnt_en <= 0;                                          //此时发送完成
                    once       <= 1'b1;
                end
            end else begin
            //没行交叠，关闭使能
                col_cnt_en <= 0;
                once       <= 1'b1;
            end
        //测试模式立即清零,,row_cnt > row_max + 1最后一个pp_flagr
        end else if(next_state == IDLE && !mode && row_cnt > row_max + 1) begin
            col_cnt_en <= 0;                                                 //此时发送完成
            once       <= 1'b1;
        //第一个低电平使能，解决多帧问题
        end else if(!hblank_in && once) begin
            col_cnt_en <= 1'b1;
            once       <= 0;
        end
    end
end


//每一行数据个数计数器，行最大值生成
always@(posedge ch_clk)
begin
    if(sclr)begin
        col_cnt    <= 0;
        col_max    <= {TIMING_CNT_WIDTH{1'b1}};         //初始化一个较大值,防止send模块状态切换提早
        hblank_low <= {TIMING_CNT_WIDTH{1'b1}};         //初始化一个较大值,防止send模块状态切换提早
    end
    else if(ce) begin
        case(next_state)
            IDLE: begin
                // col_max，hblank_low清零过早会导致发送端的交叠区卡死在行消隐,pp_flagr
                if(hblank_pos  && !vblank_in) begin     //!vbi避免最后一个hbipos影响
                    hblank_low <= col_cnt + 1;          //输入异常会影响到其值
                end
                //col_cnt_en==0代表，交叠行发送完成
                if(!col_cnt_en) begin
                    col_max <= {TIMING_CNT_WIDTH{1'b1}};//影响send的gate
                end
                //继续计数，使pp_flagr继续跳变至发送结束
                if(col_cnt == (col_max -1) || hblank_neg) begin
                    col_cnt <= 0;
                end else if(col_cnt_en) begin
                    col_cnt <= col_cnt + 1;
                end else begin
                    col_cnt <= 0;
                end
            end
            REC:begin
                //从IDLE ——> REC
                if(cur_state == IDLE) begin
                    col_cnt <= 0;
                    col_max <= col_cnt + 1;         //由于col_cnt必须从0开始计数(col_start可能为0)，因此加一
                //从IDLE ——> REC
                end else if(cur_state == NXT) begin
                    col_cnt <= 1'b0;
                end else begin
                    col_cnt <= col_cnt + 1'b1;
                end
            end
            NXT:begin
                //高电平期间继续加
                col_cnt <= col_cnt + 1'b1;
            end
            default:begin
                col_cnt <= 0;
            end
        endcase
     end
end

//每一帧多少行计数
always@(posedge ch_clk)
begin
    if(sclr)begin
        row_cnt <= 0;
    end
    else if(ce) begin
        //接收到换行或者结束即认为输入了一行,effect_width < hblank_low要求本块与交叠区域判断条件不会重复计数
        if((((next_state == NXT || (next_state == IDLE && effect_width < hblank_low)) && cur_state == REC) ||
           (next_state == IDLE && row_cnt > row_end -1 && col_cnt == effect_width)) && mode) begin  //交叠行区域，后面继续加，wait需要使用
            row_cnt <= row_cnt + 1'b1;
        //测试模式，需要用row_max判断！
        end else if(((next_state == NXT && cur_state == REC) ||
           (next_state == IDLE && row_cnt > row_max -1 && col_cnt == effect_width)) && !mode) begin //后面继续加，wait需要使用
            row_cnt <= row_cnt + 1'b1;
        //发送结束（overlap_cnt还需要使用，暂时不能清零）
        end else if(next_state == IDLE && !col_cnt_en) begin
            row_cnt <= 0;
        end
    end
end

//行计数器最大值，测试模式和hblank_low一起起作用
always@(posedge ch_clk)
begin
    if(sclr)begin
        row_max <= 0;
    end else if(ce) begin
        //防止第二帧行计数最大值变小
        if(next_state == REC && cur_state == IDLE) begin
            row_max <=0;
        //next_state == REC,防止后面为pp_flagr而产生的无效行干扰
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
        //加active_video_in以防row_start == 0 ，send_once保证一次只发送一个send_start
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
        //行消隐不得低于三个ch clk
        if(col_cnt == col_max-4 && col_max > 4 && mode && row_cnt > row_start) begin
            pp_flagw <= ~pp_flagw;
        end else if(active_neg && !mode) begin
            pp_flagw <= ~pp_flagw;
        end else if(next_state == IDLE && !col_cnt_en) begin//每一帧进行一帧重置
            pp_flagw <= 1'b1;
        end
    end
end

//乒乓读操作标志位生成
//读地址提前hbblank_out_neg两个clk赋值
//在整个hblank_out低电平控制输出数据,addr,dout，见data_save.v
always @(posedge ch_clk) begin
    if(sclr) begin
        pp_flagr <= 1'b1;
        wait_ <= 0;
    end else if(ce) begin
        //换行阶段暂停一次变换
        if((row_cnt == row_end + 2) && mode) begin
            wait_ <= 1'b1;
        end else begin
            wait_ <= 0;
        end
        //要保证输出行消隐时间大于3clk
        if(col_cnt == col_max - 2 && !wait_) begin
            pp_flagr <= ~pp_flagr;
        //每一帧进行一帧重置
        end else if(send_start) begin
            pp_flagr <= 1'b1;
        end
    end
end



//缓存行数
always @(posedge ch_clk) begin
    if(sclr) begin
        //初值全1原因：第一次均未使用，是为下一次清零准备
        row_save_cnt1 <= (TOP_BOTTOM_SEL && !FRAME_RAM_EN && mode) ? ((OVERLAP_WIDTH-1)/2): 0;
        row_save_cnt2 <= (TOP_BOTTOM_SEL && !FRAME_RAM_EN && mode) ? ((OVERLAP_WIDTH-1)/2): 0;
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
        wr_addr1 <= reverse_en ? effect_width-1:0;
        wr_addr2 <= reverse_en ? effect_width-1:0;
    //有效行区间
    end else if(ce) begin
        // 一行数据接收完成，地址初值
        if(next_state == NXT) begin
            if(pp_flagw) begin
                wr_addr1 <= reverse_en ? (effect_width*(row_save_cnt1 + 1'b1) - 1'b1):(effect_width*row_save_cnt1);
            end else begin
                wr_addr2 <=  reverse_en ? (effect_width*(row_save_cnt2 + 1'b1) - 1'b1):(effect_width*row_save_cnt2);
            end
        //未接收完，在有效列区间
        end else if(effect_reigon) begin
            if(pp_flagw) begin
                wr_addr1 <= reverse_en ? (wr_addr1 - 1'b1):(wr_addr1 + 1'b1);
            end else begin
                wr_addr2 <= reverse_en ? (wr_addr2 - 1'b1):(wr_addr2 + 1'b1);
            end
        //一帧数据接受完成，地址重置
        end else if(next_state == IDLE) begin
            wr_addr1 <= reverse_en ? effect_width-1:0;
            wr_addr2 <= reverse_en ? effect_width-1:0;
        end
    end
end

always @(posedge ch_clk) begin
    if(sclr) begin
        effect_width  <= 0; //有效宽度
        effect_row    <= 0; //有效行
        row_save      <= 0; //每个RAM缓存行数
    end else if(ce) begin
        effect_width  <= mode ? (col_end - col_start + 1'b1):hblank_low;
        effect_row    <= (row_cnt >= row_start) && (row_cnt <= row_end);
        row_save      <= (TOP_BOTTOM_SEL && !FRAME_RAM_EN && mode) ? ((OVERLAP_WIDTH-1)/2):1'b0;
    end
end

//有效区域信号生成
always @(posedge ch_clk) begin
    if(sclr) begin
        effect_reigon <= 0;
    end else if(ce) begin
        //正常模式取决于col_start,col_end,row_start,row_end
        if(mode) begin
            //col_start > 0时，每一行的第一个数据不需要接收,整体前移，所以&& col_cnt < col_end，下同
            if(col_start > 0) begin
                //一行最开头的时候，col_cnt==col_max - 1,但是不应该接收
                if((cur_state == IDLE || cur_state == NXT) && next_state ==REC) begin
                    effect_reigon <= 0;
                end else begin
                    effect_reigon <= (col_start - 1 <= col_cnt && col_cnt < col_end &&  effect_row && next_state == REC);
                end
            end else begin
                //col_start = 0，一行最开头的时候，col_cnt = col_max -1,应该接收，col有效
                if((cur_state == IDLE || cur_state == NXT) && next_state ==REC) begin//=0
                    effect_reigon <= effect_row;
                //col_start = 0, 除去每行第一个数据之后的数据
                end else begin
                    effect_reigon <= (((col_cnt >= 0 && col_cnt < col_end) ||
                                    (col_cnt == col_max-1)) && effect_row && (next_state == REC));
                end
            end
        //测试模式接收全部数据
        end else begin
            effect_reigon <= active_video_in;
        end
    end
end

//  The following function calculates the address width based on specified RAM depth
function integer clogb2;
    input integer depth;
    for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
endfunction


`ifdef  DEBUG_MODE
//判断hblank_in高电平周期是否满足
assign hbi_high = (hblank_low-1) <= col_cnt && col_cnt <= (col_max - 2) && row_cnt > 0 ? 1'b1 : 1'b0;
assign hblank_err = hbi_high ? (hblank_in  ? 1'b0:1'b1) : 1'b0;
`endif

endmodule
