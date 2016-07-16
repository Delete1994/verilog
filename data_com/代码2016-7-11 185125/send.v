//========================================================================================
//  Filename      : send.v
//  Created On    : 2016-06-29 14:59:58
//  Author        : PanShen
//  Email         : pan_shen@foxmail.com
//  Copyright (c) 2014-2016 All rights reserved
//========================================================================================
//2016年7月4日22:05:40去掉send_start采沿

module send(
    sclr,
    ce,
    clk,
    mode,
    sel,

    hblank_out,
    vblank_out,
    active_video_out,
    video_data_out,

    row_start,
    row_end,
    col_start,
    col_end,
    switch,

    //for main
    addr_m,
    dout_m,
    enb,
    //for left or right
    addr_sl,
    dout_sl,
    ena_sl,

    addr_sr,
    dout_sr,
    ena_sr,

    col_max,
    row_max,
    hblank_low,
    send_start
);


parameter CHANNEL_IN_NUM   = 4;       //输入数据块数量2^6 == 63
parameter CHANNEL_OUT_NUM  = 2;       //输出数据块数量
parameter VIDEO_DATA_WIDTH = 18;      //视频数据信号宽度
parameter RAM_DEPTH        = 100;     //行缓存ram深度
parameter TIMING_CNT_WIDTH = 10;      //行、列计数器信号宽度
parameter OVERLAP_WIDTH    = 2;       //输出数据块交叠量
parameter TOP_BOTTOM_SEL   = 1'd1;    //输入数据块由上、下部分组成标识
parameter HEAD_DIRECTION   = 1'd0;    //抽头方向0全左,1全右,2对半分
parameter FRAME_RAM_EN     = 1'd0;    //帧缓存使能
parameter OUTPUT_DIRECTION = 0;       //输入数据块的读出方向
parameter CH               = 0;
//一个发送块包含多少个输入块，输出计数器是输入的多少倍
localparam TIMES           = CHANNEL_IN_NUM/CHANNEL_OUT_NUM;
//根据RAM深度决定RAM操作的地址宽度
localparam ADDR_WIDTH      = clogb2(RAM_DEPTH-1'b1);
localparam OVERLAP_W       = clogb2(OVERLAP_WIDTH+1);
//是否有读冲突
localparam NO_COLLIDE      = (CHANNEL_IN_NUM != CHANNEL_OUT_NUM ||
                             (!TOP_BOTTOM_SEL &&  CHANNEL_OUT_NUM <= 2) ||
                             (TOP_BOTTOM_SEL && CHANNEL_OUT_NUM <= 4));
//输入输出一个块，左右均填充自己
localparam ONE_BLOCK       = (CHANNEL_OUT_NUM == 1) || (TOP_BOTTOM_SEL && CHANNEL_OUT_NUM == 2);
//左边块
localparam LEFT_BLOCK      = ((TOP_BOTTOM_SEL==1 &&  CH == 0) ||         //左上
                             (!TOP_BOTTOM_SEL && CH == 0)) ||            //一行最左边
                             (TOP_BOTTOM_SEL && CH == CHANNEL_OUT_NUM-1);//左下
//右边块
localparam RIGHT_BLOCK     = ((TOP_BOTTOM_SEL && CH == (CHANNEL_OUT_NUM>>1)-1) ||
                             (!TOP_BOTTOM_SEL && CH == CHANNEL_OUT_NUM-1) ) ||
                             (TOP_BOTTOM_SEL && CH == CHANNEL_OUT_NUM>>1);
//中间块
localparam MIDD_BLOCK      = ((!TOP_BOTTOM_SEL && (0 < CH && CH < CHANNEL_OUT_NUM-1)) ||             //一排中间
                             (TOP_BOTTOM_SEL && (0 < CH && CH < CHANNEL_OUT_NUM/2 -1))) ||           //上排中间
                             (TOP_BOTTOM_SEL && (CHANNEL_OUT_NUM/2 < CH && CH < CHANNEL_OUT_NUM-1 ));//两排下排中间
//左边镜像填充自己左边
localparam FILL_SELF_L     = (TOP_BOTTOM_SEL && CH == CHANNEL_OUT_NUM-1'b1) || CH == 6'd0;
//右边镜像填充自己右边
localparam FILL_SELF_R     = (TOP_BOTTOM_SEL && (CH == (CHANNEL_OUT_NUM>>1'b1)-1'b1 ||
                                             CH == CHANNEL_OUT_NUM>>1'b1))  ||
                            (!TOP_BOTTOM_SEL && CH == CHANNEL_OUT_NUM-1'b1);
//下边块，midd_cnt从左到右递减
localparam DOWN_BLOCK      = TOP_BOTTOM_SEL && (CH >= CHANNEL_OUT_NUM/2);

localparam IDLE            = 6'b000001;//空闲等待
localparam HEAD            = 6'b000010;//准备开头阶段
localparam LEFT            = 6'b000100;//左边块
localparam MIDDLE          = 6'b001000;//中间块
localparam RIGHT           = 6'b010000;//右边块
localparam NEXT            = 6'b100000;//换行

input                                           clk;    // Clock
input                                           sclr;   //synchronized clear
input                                           ce;     // Clock Enable
input                                           mode;
input                                           sel;
input [TIMING_CNT_WIDTH-1'b1:0]                 row_start;
input [TIMING_CNT_WIDTH-1'b1:0]                 row_end;
input [TIMING_CNT_WIDTH-1'b1:0]                 col_start;
input [TIMING_CNT_WIDTH-1'b1:0]                 col_end;
input [TIMING_CNT_WIDTH-1'b1:0]                 col_max;
input [TIMING_CNT_WIDTH-1'b1:0]                 row_max;
input [TIMING_CNT_WIDTH-1'b1:0]                 hblank_low;
//other signal
input                                           send_start;
input [TIMES*VIDEO_DATA_WIDTH-1'b1:0]           dout_m;
input [VIDEO_DATA_WIDTH-1'b1:0]                 dout_sl;
input [VIDEO_DATA_WIDTH-1'b1:0]                 dout_sr;

output                                          hblank_out;
output                                          vblank_out;
output                                          active_video_out;
output [VIDEO_DATA_WIDTH-1'b1 :0]               video_data_out;
//一个大块TIMES个小块，每个RAM地址ADDRB
output [TIMES*ADDR_WIDTH-1'b1:0]                addr_m;
output [ADDR_WIDTH-1'b1:0]                      addr_sl;
output [ADDR_WIDTH-1'b1:0]                      addr_sr;
output [TIMES-1:0]                              enb;
output                                          ena_sl;
output                                          ena_sr;
output                                          switch;
//output reg
//在hb,vb,av前一个clk生成
reg                                             hblank_out_b1;
reg                                             vblank_out_b1;
reg                                             active_video_out_b1;
reg                                             hblank_out_b2;
reg                                             vblank_out_b2;
reg                                             active_video_out_b2;
reg                                             hblank_out_b3;
reg                                             vblank_out_b3;
reg                                             active_video_out_b3;

reg                                             switchb3;
reg                                             switchb2;
reg                                             switchb1;
reg                                             switch;             //切换通道

reg                                             hblank_out;
reg                                             vblank_out;
reg                                             active_video_out;
reg    [VIDEO_DATA_WIDTH-1'b1 :0]               video_data_out;

reg    [TIMES*ADDR_WIDTH-1'b1:0]                addr_m;
reg    [ADDR_WIDTH-1'b1:0]                      addr_sl;
reg    [ADDR_WIDTH-1'b1:0]                      addr_sr;
reg    [TIMES-1:0]                              enb;
reg                                             ena_sl;
reg                                             ena_sr;
//other reg
reg    [TIMING_CNT_WIDTH*TIMES-1'b1:0]          col_cnt;          //行计数器，用于保持hblankin一样的时间
reg    [TIMING_CNT_WIDTH     :0]                row_cnt;          //列计数器，计算已发送的行数
reg    [ADDR_WIDTH -1'b1:0]                     side_ptr;         //侧边指针生成
reg    [ADDR_WIDTH -1'b1:0]                     midd_ptr;         //中间指针生成
reg    [clogb2(TIMES-1):0]                      midd_cnt;         //计算中间发送块个数
reg    [clogb2(TIMES-1):0]                      midd_cnt_d1;      //计算中间发送块个数
reg    [clogb2(TIMES-1):0]                      midd_cnt_d2;      //计算中间发送块个数
reg    [clogb2(TIMES-1):0]                      midd_cnt_d3;      //计算中间发送块个数
//FSM reg
reg    [5:0]                                    cur_state;
reg    [5:0]                                    next_state;
reg    [5:0]                                    next_state_d2;
reg    [5:0]                                    next_state_d3;    //写地址1clk延时,读RAM存在2个周期的延时！
// reg    [5:0]                                    next_state_d4;
//行交叠使用
reg    [OVERLAP_W-1:0]                          overlap_cnt;      //行交叠计数器
reg    [OVERLAP_W-1:0]                          col_read_cnt;     //指示已经读取几行数据
reg                                             twice;            //每读完两行，col_read_cnt加一
reg                                             down;
reg                                             ch_dir;
//自己要发的行数
reg    [TIMING_CNT_WIDTH     :0]                own_row;
//输入块的有效数据宽度
reg    [TIMING_CNT_WIDTH-1'b1:0]                effect_width_i;
//列计数器顶端，NEXT状态结束条件
reg    [TIMING_CNT_WIDTH*TIMES-1'b1:0]          next_gate;
//wire
//输入块的有效数据宽度
// wire   [TIMING_CNT_WIDTH-1'b1:0]                effect_width_i;
//MIDELE状态结束条件，即col_cnt计到此值则结束MIDDLE状态
reg    [TIMING_CNT_WIDTH*TIMES-1'b1:0]          middle_gate;
//正常模式下，一行总有效像素个数，right,left状态结束条件
reg    [TIMING_CNT_WIDTH*TIMES-1'b1:0]          right_left_gate;
//列计数器顶端，NEXT状态结束条件
// wire   [TIMING_CNT_WIDTH*TIMES-1'b1:0]          next_gate;
//行计数器顶端
reg    [TIMING_CNT_WIDTH     :0]                all_row;
// //自己要发的行数
// wire   [TIMING_CNT_WIDTH     :0]                own_row;
//自己块发完了
reg                                             own_finish;
reg    [OVERLAP_W-1:0]                          col_save;           //缓存多少行数据
reg                                             output_dir;
reg                                             midd_cnt_dir;
reg    [TIMES*ADDR_WIDTH-1'b1:0]                offset;           //偏移量，共用乘法器

//state refresh
always@(posedge clk)begin
    if(sclr)begin
        cur_state <= IDLE;
        next_state_d2 <= IDLE;
    end else begin
        cur_state <= next_state;
        next_state_d2 <= cur_state;
        next_state_d3 <= next_state_d2;
        // next_state_d4 <= next_state_d3;
    end
end

//发送状态机跳转条件
always@(*)
begin
    if(ce) begin
        case(cur_state)
            IDLE: begin
                //开始发送
                if(send_start) begin
                    next_state = HEAD;
                end else begin
                    next_state = IDLE;
                end
            end
            HEAD: begin
                if(col_cnt == next_gate)begin
                    //mode=1,正常
                    if(mode) begin
                        //1:右抽头
                        if(output_dir) begin
                            next_state = RIGHT;
                        //0: 左抽头
                        end else begin
                            next_state = LEFT;
                        end
                    //mode=0,测试
                    end else begin
                        next_state = MIDDLE;
                    end
                end else begin
                    next_state = HEAD;
                end
            end
            LEFT: begin
                if(col_cnt == OVERLAP_WIDTH-1 || col_cnt == right_left_gate-1) begin
                    if(row_cnt == all_row && col_cnt == right_left_gate-1) begin
                        next_state = IDLE;
                    //1:右抽头
                    end else if(output_dir) begin
                        next_state = NEXT;//发完换行
                    //0: 左抽头
                    end else begin
                        next_state = MIDDLE;
                    end
                end else begin
                    next_state = LEFT;
                end
            end
            MIDDLE: begin
                if(col_cnt == middle_gate) begin//除去交叠的有效宽度
                    //mode=1,正常模式
                    if(mode) begin
                        //1:右抽头
                        if(output_dir) begin
                            next_state = LEFT;
                        //0: 左抽头
                        end else begin
                            next_state = RIGHT;
                        end
                    //mode=0,测试
                    end else begin
                        if(row_cnt == all_row) begin
                            next_state = IDLE;
                        end else begin
                            next_state = NEXT;
                        end
                    end
                end else begin
                    next_state = MIDDLE;
                end
            end
            RIGHT:  begin
                if(col_cnt == OVERLAP_WIDTH-1 || col_cnt == right_left_gate-1) begin
                    if(row_cnt == all_row && col_cnt == right_left_gate-1) begin
                        next_state = IDLE;
                    end else if(output_dir) begin
                        next_state = MIDDLE;
                    //0: 左抽头
                    end else begin
                        next_state = NEXT;//发完换行
                    end
                end else begin
                    next_state = RIGHT;
                end
            end
            NEXT: begin
                //高电平时间凑齐了，开始继续发送数据
                if(col_cnt == next_gate) begin
                    //正常模式
                    if(mode) begin
                        //1:右抽头
                        if(output_dir) begin
                            next_state = RIGHT;
                        //0: 左抽头
                        end else begin
                            next_state = LEFT;
                        end
                    //测试模式
                    end else begin
                        next_state = MIDDLE;
                    end
                end else begin
                    next_state = NEXT;
                end
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end else
        next_state = IDLE;
end


//发送计数器处理
always@(posedge clk)
begin
    if(sclr) begin
        col_cnt <= 0;
        row_cnt <= 0;
    end else if(ce) begin
        case(next_state)
            IDLE: begin
                col_cnt <= 0;
                row_cnt <= 0;
            end
            HEAD: begin
                //必须采沿，后面还要计数
                //加上上一个状态的约束则可不用采沿
                if(send_start && cur_state == IDLE) begin
                    col_cnt    <= 0;
                end else begin
                    col_cnt    <= col_cnt + 1'b1;
                end
            end
            LEFT,MIDDLE,RIGHT,NEXT: begin
                if(col_cnt == next_gate) begin
                    col_cnt <= 1'b0;
                    row_cnt <= row_cnt +1'b1;
                end else begin
                    col_cnt    <= col_cnt + 1'b1;
                end
            end
            default : col_cnt <= 0;
        endcase
    end
end


//产生hblank_out,vblank_out,active_video_out的时序
always@(posedge clk)
begin
    if(sclr) begin
        hblank_out_b3       <= 1'b1;
        vblank_out_b3       <= 1'b1;
        active_video_out_b3 <= 1'b0;
    end else if(ce) begin
        case(next_state)
            IDLE: begin
                hblank_out_b3       <= 1'b1;
                vblank_out_b3       <= 1'b1;
                active_video_out_b3 <= 1'b0;
            end
            HEAD: begin
                //电平部分时序凑齐了
                //若vbo没有在hbo上升沿变化，应该是gate没有及时变话
                if(col_cnt >= right_left_gate) begin
                    hblank_out_b3 <= 1'b1;
                    vblank_out_b3 <= 1'b0;
                ////电平部分时序还没凑齐
                end else begin
                    hblank_out_b3 <= 1'b0;
                    vblank_out_b3 <= 1'b1;
                end
            end
            LEFT,MIDDLE,RIGHT: begin
                if((col_cnt == right_left_gate-1 && mode) || (col_cnt == middle_gate && !mode)) begin
                    hblank_out_b3 <= 1'b1;
                    active_video_out_b3 <= 1'b0;
                    if(row_cnt == all_row) begin//一帧结束
                        vblank_out_b3 <= 1'b1;
                    end else begin//换行而已
                        vblank_out_b3 <= 1'b0;
                    end
                end else begin
                    active_video_out_b3 <= 1'b1;
                    hblank_out_b3       <= 1'b0;
                    vblank_out_b3       <= 1'b0;
                end
            end
            NEXT: begin
                active_video_out_b3 <= 1'b0;
                hblank_out_b3       <= 1'b1;
                vblank_out_b3       <= 1'b0;
            end
            default : /* default */;
        endcase
    end
end

//时序延时
always @(posedge clk) begin
    if(sclr) begin
        hblank_out          <= 1;
        vblank_out          <= 1;
        active_video_out    <= 0;
        hblank_out_b1       <= 1;
        vblank_out_b1       <= 1;
        active_video_out_b1 <= 0;
        hblank_out_b2       <= 1;
        vblank_out_b2       <= 1;
        active_video_out_b2 <= 0;
    end else if(ce) begin
        hblank_out_b2       <= hblank_out_b3;
        vblank_out_b2       <= vblank_out_b3;
        active_video_out_b2 <= active_video_out_b3;
        hblank_out_b1       <= hblank_out_b2;
        vblank_out_b1       <= vblank_out_b2;
        active_video_out_b1 <= active_video_out_b2;
        hblank_out          <= hblank_out_b1;
        vblank_out          <= vblank_out_b1;
        active_video_out    <= active_video_out_b1;
    end
end


//侧块发送指针
always@(posedge clk)
begin
    if(sclr) begin
        side_ptr <= 0;
    end else if(ce) begin
        case(next_state)
            //第一个侧块的指针初始化
            HEAD,NEXT: begin
                //从左到右，左边块初始化
                if(!output_dir) begin
                    if(FILL_SELF_L) begin//镜像自己-
                        side_ptr <= OVERLAP_WIDTH;
                    end else begin//顺序填充左边相邻块+
                        side_ptr <= effect_width_i - OVERLAP_WIDTH;
                    end
                //从右到左,右边块初始化,+
                end else begin
                    if(FILL_SELF_R)begin
                        //右边镜像自己块
                        side_ptr <= effect_width_i - OVERLAP_WIDTH-1'b1;
                    end else begin
                        //顺序填充右边相邻快
                        side_ptr <= OVERLAP_WIDTH-1;
                    end
                end
            end
            LEFT:begin
                if(!output_dir) begin
                    //自身镜像从左到右都是减
                    if(FILL_SELF_L) begin
                        if(side_ptr==1) begin
                            side_ptr <= 1;
                        end else begin
                            side_ptr <= side_ptr - 1'b1;
                        end
                    //非自身镜像从左到右都是加
                    end else begin
                        if(side_ptr == effect_width_i - 1) begin
                            side_ptr <= effect_width_i - 1;
                        end else begin
                            side_ptr <= side_ptr + 1'b1;
                        end
                    end
                end else if(output_dir)begin
                    //自身镜像从右到左都是加
                    if(FILL_SELF_L) begin
                        if(side_ptr==OVERLAP_WIDTH) begin
                            side_ptr <= OVERLAP_WIDTH;
                        end else begin
                            side_ptr <= side_ptr + 1'b1;
                        end
                    //非自身镜像从右到左都是减
                    end else begin
                        if(side_ptr == effect_width_i - OVERLAP_WIDTH) begin
                            side_ptr <= effect_width_i - OVERLAP_WIDTH;
                        end else begin
                            side_ptr <= side_ptr - 1'b1;
                        end
                    end
                end
            end
            MIDDLE: begin
                //从左到右，右边块初始化，
                if(!output_dir) begin
                    if(FILL_SELF_R) begin//右边填充自己 01234 32 -
                        side_ptr <= effect_width_i - 2;
                    end else begin//右边填充相邻，顺序 01 01234
                        side_ptr <= 0;
                    end
                //从右到左,左边块初始化，
                end else begin
                    if(FILL_SELF_L) begin//镜像自己21 01234 32+
                        side_ptr <= 1;
                    end else begin//顺序填充左边相邻块01234 34 -
                        side_ptr <= effect_width_i-1'b1;
                    end
                end
            end
            RIGHT:begin
                //自身镜像从左到右都是减
                if(!output_dir) begin
                    if(FILL_SELF_R) begin
                        if(side_ptr==effect_width_i-1'b1-OVERLAP_WIDTH) begin
                            side_ptr <= effect_width_i-1'b1-OVERLAP_WIDTH;
                        end else begin
                            side_ptr <= side_ptr - 1'b1;
                        end
                    end else begin
                        if(side_ptr==OVERLAP_WIDTH-1) begin
                            side_ptr <= OVERLAP_WIDTH-1;
                        end else begin
                            side_ptr <= side_ptr + 1'b1;
                        end
                    end
                //自身镜像从右到左都是加
                end else if(output_dir)begin
                    if(FILL_SELF_R) begin
                        if(side_ptr==effect_width_i - 2) begin
                            side_ptr <= effect_width_i - 2;
                        end else begin
                            side_ptr <= side_ptr + 1'b1;
                        end
                    end else begin
                        if(side_ptr==0) begin
                            side_ptr <= 0;
                        end else begin
                            side_ptr <= side_ptr - 1'b1;
                        end
                    end
                end
            end
            default:;
        endcase
    end
end

//中间块标志计数器,上边块和下边块相反
always@(posedge clk)
begin
    if(sclr) begin
        midd_cnt    <= midd_cnt_dir ? (TIMES-1) : 0;
        midd_cnt_d1 <= 0;
        midd_cnt_d2 <= 0;
        midd_cnt_d3 <= 0;
    end else if(ce) begin
        midd_cnt_d1 <= midd_cnt;
        midd_cnt_d2 <= midd_cnt_d1;
        midd_cnt_d3 <= midd_cnt_d2;
        case(next_state)
            MIDDLE: begin
                if((midd_ptr == effect_width_i - 1'b1 && !output_dir) ||//一个块加到最大
                   (midd_ptr == 0 && output_dir)) begin//一个块减到最小
                    if(!midd_cnt_dir) begin
                        if(midd_cnt == TIMES-1) begin//加到末尾快
                            midd_cnt <= midd_cnt;
                        //下一个中间块
                        end else begin
                            midd_cnt <= midd_cnt + 1'b1;
                        end
                    end else begin
                        if(midd_cnt == 0) begin//减到开头快
                            midd_cnt <= midd_cnt;
                        end else begin
                            midd_cnt <= midd_cnt - 1'b1;
                        end
                    end
                end
            end
            NEXT:begin
                midd_cnt <= midd_cnt_dir ? (TIMES-1) : 0;
            end
            IDLE,HEAD: begin//RIGHT,LEFT状态midd_cnt还不能变
                //从左到右输出升序，,从右到左降序，OVERLAP_WIDTH->1
                //effect_width_i 在HEAD生效
                midd_cnt <= midd_cnt_dir ? (TIMES-1) : 0;
            end
            default:;
        endcase
    end
end


//中间块发送指针,中间块标志计数器,上边块和下边块相反
always@(posedge clk)
begin
    if(sclr) begin
        midd_ptr <= 0;
    end else if(ce) begin
        case(next_state)
            MIDDLE: begin
                //从左到右加到最大
                if(midd_ptr == effect_width_i - 1'b1 && !output_dir) begin
                    //中间块全部发完
                    if(midd_cnt == TIMES-1) begin
                        midd_ptr <= 0;
                    //下一个中间块
                    end else begin
                        midd_ptr <= 0;
                    end
                //从右到左减到最小
                end else if(midd_ptr == 0 && output_dir) begin
                    if(midd_cnt == 0) begin
                        midd_ptr <= 0;
                    end else begin
                        midd_ptr <= effect_width_i - 1'b1;
                    end
                //从左到右输出升序，,从右到左降序
                end else if(!output_dir) begin
                    midd_ptr <= midd_ptr + 1'b1;
                end else if(output_dir)begin
                    midd_ptr <= midd_ptr - 1'b1;
                end
            end
            LEFT,RIGHT,IDLE,HEAD,NEXT:begin
                midd_ptr <= output_dir ?  effect_width_i - 1'b1 : 0;
            end
            default:;
        endcase
    end
end


//把一行末尾那个数保留下来，给sel使用
// //next_state --> cur_state --> next_state_d2 --> next_state_d3
// always @(posedge clk) begin
//     if(sclr) begin
//         hold_last_one <= 0;
//     end else if(ce) begin
//         //正常模式
//         if((next_state_d3== IDLE || next_state_d3 == NEXT) && mode &&
//            // ((next_state_d3 == RIGHT && !output_dir) ||//从左到右最后一块
//            // (next_state_d3 == LEFT  && output_dir))) begin //从右到左最后一块
//            ((next_state_d4 == RIGHT) ||//从左到右最后一块
//            (next_state_d4 == LEFT))) begin //从右到左最后一块
//             hold_last_one <= video_data_out;
//         //测试模式
//         end else if((next_state_d3== IDLE || next_state_d3 == NEXT) && !mode && next_state_d4 == MIDDLE ) begin
//             hold_last_one <= video_data_out;
//         end
//     end else begin
//         hold_last_one <= 0;
//     end
// end



//已读行数计数器处理
always@(posedge clk)
begin
    if(sclr) begin
        col_read_cnt <= 0;
    end else if(ce) begin
        case(next_state)
            IDLE: begin
                col_read_cnt <= 0;
            end
            LEFT,MIDDLE,RIGHT,NEXT: begin
                if(col_cnt == right_left_gate) begin//一行结束
                    if(twice) begin
                        if(col_read_cnt == col_save && !down) begin//读完了那几行
                            col_read_cnt <= 0;
                        end else if(col_read_cnt == 0 && down) begin
                            col_read_cnt <= col_save;
                        end  else begin
                            col_read_cnt <= down ? col_read_cnt - 1 : col_read_cnt +1'b1;
                        end
                    end
                end
            end
            default : ;
        endcase
    end
end


//交叠行数计数器处理
always@(posedge clk)
begin
    if(sclr) begin
        overlap_cnt  <= 0;
    end else if(ce) begin
        case(next_state)
            IDLE: begin
                overlap_cnt <= 0;
            end
            LEFT,MIDDLE,RIGHT,NEXT: begin
                if(own_finish && col_cnt == next_gate) begin
                    overlap_cnt <= overlap_cnt +1'b1;
                end
            end
            default : ;
        endcase
    end
end

////每两行col_read_cnt加一（一个乒乓周期）
always@(posedge clk)
begin
    if(sclr) begin
        twice        <= 0;
        down         <= 0;
    end else if(ce) begin
        case(next_state)
            IDLE: begin
                twice <= 0;
                down <= 0;
            end
            LEFT,MIDDLE,RIGHT,NEXT: begin
                //自己块发完，开始处理交叠区
                if(own_finish && overlap_cnt == 0) begin//重新开始
                    down <= 1;
                    if(own_row%2 ==0) begin//偶数
                        twice <= 0;
                    end else begin //奇数47 1， 89 0
                        twice <= 1;
                    end
                end else if(col_cnt == right_left_gate) begin//一行结束
                    twice <= ~twice;//每两行加一（一个乒乓周期）
                end
            end
            default : ;
        endcase
    end
end

//通道方向切换
always@(posedge clk)
begin
    if(sclr) begin
        ch_dir <= 1'b0;
    end else if(ce) begin
        case(next_state)
            HEAD: begin
                ch_dir <= 1'b0;
            end
            LEFT,MIDDLE,RIGHT,NEXT: begin
                //方向切换要提前,地址赋值提前2clk
                if(own_finish && col_cnt == next_gate-2) begin
                    ch_dir <= 1'b1;
                end
            end
            default : ;
        endcase
    end
end


//通道切换
always@(posedge clk)
begin
    if(sclr) begin
        switchb3     <= 1'b0;
        switchb2     <= 1'b0;
        switchb1     <= 1'b0;
        switch       <= 1'b0;
    end else if(ce) begin
        {switch,switchb1,switchb2} <= {switchb1,switchb2,switchb3};
        case(next_state_d2)
            HEAD:begin
                switchb3 <= 1'b0;//晚一点才能清零
            end
            LEFT,MIDDLE,RIGHT,NEXT: begin
                if(own_finish && col_cnt == next_gate) begin
                    switchb3 <= 1'b1;
                end
            end
            default : ;
        endcase
    end
end




//插寄存器，改变建立时间
always @(posedge clk) begin
    if(sclr) begin
        own_row         <= 0;
        next_gate       <= 0;
        middle_gate     <= 0;
        right_left_gate <= 0;
        all_row         <= 0;
        offset          <= 0;
        own_finish      <= 0;
        col_save        <= 0;
        midd_cnt_dir    <= 0;
        output_dir      <= 0;
        effect_width_i  <= 0;
    end else if(ce) begin
        next_gate       <= (col_max*TIMES) - 1'b1;//行计数器顶端，时钟数乘以频率倍数，换行条件
        own_row         <= mode ? (row_end - row_start +1'b1) : row_max + 1;
        middle_gate     <= mode ? (effect_width_i*TIMES + OVERLAP_WIDTH-1) : (effect_width_i*TIMES - 1);
        right_left_gate <= mode ? (effect_width_i*TIMES + (OVERLAP_WIDTH<<1'b1)) : (effect_width_i*TIMES - 1);
        all_row         <= mode ? ((TOP_BOTTOM_SEL && !FRAME_RAM_EN ) ? (own_row + OVERLAP_WIDTH) : own_row) : own_row;
        offset          <= mode ? (col_read_cnt*effect_width_i) : 0;
        own_finish      <= row_cnt >  own_row - 1;//0-5偶数列,switch
        col_save        <= (TOP_BOTTOM_SEL && !FRAME_RAM_EN) ? (OVERLAP_WIDTH-1)/2:1'b0;//注意和eceive保持一致！！
        midd_cnt_dir    <= DOWN_BLOCK ? (!output_dir) : output_dir;
        output_dir      <= (OUTPUT_DIRECTION[CH] && !ch_dir) || (OUTPUT_DIRECTION[CHANNEL_OUT_NUM - 1 - CH] && ch_dir);
        effect_width_i  <= mode ? (col_end - col_start + 1'b1) : hblank_low;
    end
end

// //保证同步变化
// always@(posedge clk) begin
//     effect_width_i = mode ? (col_end - col_start + 1'b1) : hblank_low;
// end

//为了保证发送状态机hblank_out、vblnak_out与hblank_in、vblank_in的高低电平周期一致，从输入模块传入row_max参数，
//乘以TIMES倍后作为发送状态机行消隐门限（next_gate），即hblank_out两个下降沿之间的时钟个数，如此即可达到要求。
//（TIMES为输入块除以输出块的结果）
//
//对于两侧的输出块，外侧（左边输出块的左侧，右边输出块的右侧）有镜像填充，
//内侧（左边输出块的右侧，右边输出块的左侧）有其他块顺序填充，
//对于中间的输出块，两侧有其他块的顺序填充，这样会存在读取数据的冲突问题，如下图

//减一是因为0-n有n+1个数，不减一是因为组合逻辑反应很快！！！
//读取的有效数据宽度
// assign effect_width_i = mode ? (col_end - col_start + 1'b1) : hblank_low;//输入块的有效数据宽度
//MIDELE状态结束条件，即col_cnt计到此值则结束MIDDLE状态
// assign middle_gate = mode ? (effect_width_i*TIMES + OVERLAP_WIDTH-1) : (effect_width_i*TIMES - 1);
//一行总有效像素个数，right,left状态结束条件 6+6 = 12
// assign right_left_gate = mode ? (effect_width_i*TIMES + (OVERLAP_WIDTH<<1'b1)) : (effect_width_i*TIMES - 1);
//计数器顶端，NEXT状态结束条件
// assign next_gate = (col_max*TIMES) - 1'b1;//行计数器顶端，时钟数乘以频率倍数，换行条件
//不含有交叠行数
// assign own_row = mode ? (row_end - row_start +1'b1) : row_max + 1;
//FRAME_RAM_EN:一行填充,帧缓存使能，不进行行填充,测试模式发所有
// assign all_row = mode ? ((TOP_BOTTOM_SEL && !FRAME_RAM_EN ) ? (own_row + OVERLAP_WIDTH) : own_row) : own_row;
//自己块发完了，该发交叠区域了
// assign own_finish = row_cnt >  own_row - 1;//0-5偶数列,switch
//存了几行
// assign col_save = (TOP_BOTTOM_SEL && !FRAME_RAM_EN) ? (OVERLAP_WIDTH-1)/2:1'b0;//注意和eceive保持一致！！
//自己块的方向+交叠快的方向
// assign output_dir = (OUTPUT_DIRECTION[CH] && !ch_dir) || (OUTPUT_DIRECTION[CHANNEL_OUT_NUM - 1 - CH] && ch_dir);
//基地址偏移量,多行处理，，，<< (midd_cnt*ADDR_WIDTH)多块处理
// assign offset  = mode ? (col_read_cnt*effect_width_i) : 0;
//中间块递增还是递减
// assign midd_cnt_dir = DOWN_BLOCK ? (!output_dir) : output_dir;

////midd_cnt,中间块数计数器，行数计数器

generate
    if(ONE_BLOCK)begin
        always@(posedge clk) begin
            if(sclr) begin
                addr_sr <= 0;
                ena_sr  <= 0;
                addr_sl <= 0;
                ena_sl  <= 0;
                addr_m <= 0;
                enb <= 0;
            end else if(ce) begin
                case(next_state_d2)
                    LEFT,RIGHT:begin
                        if(next_state==MIDDLE) begin//为下一块做准备
                            enb <= 1<<midd_cnt;
                            addr_m <= midd_ptr + offset << (midd_cnt*ADDR_WIDTH);
                        end else begin
                            enb <= 1<<midd_cnt;
                            addr_m <= side_ptr + offset << (midd_cnt*ADDR_WIDTH);
                        end
                    end
                    MIDDLE:begin
                        if(next_state==RIGHT || next_state  == LEFT) begin//为下一块做准备
                            enb <= 1<<midd_cnt;
                            addr_m <= side_ptr + offset << (midd_cnt*ADDR_WIDTH);
                        end else begin
                            enb <= 1<<midd_cnt;
                            addr_m <= midd_ptr +offset << (midd_cnt*ADDR_WIDTH);
                        end
                    end
                    default: begin
                        //只提前2clk周期初始化，低功耗考虑
                        if((col_cnt  == next_gate) || (col_cnt  == 0 && next_state_d2 != IDLE)) begin
                            if(mode) begin//正常模式，初始化侧边指针//CH <= 0
                                //如果交叠只有一，则会错过MIDDLE的初始化，因此需要加入判断
                                if(next_state  == MIDDLE) begin
                                    enb <= 1<<midd_cnt;
                                    addr_m <= midd_ptr + offset << (midd_cnt*ADDR_WIDTH);
                                end else begin
                                    enb <= 1<<midd_cnt;
                                    addr_m <= side_ptr + offset << (midd_cnt*ADDR_WIDTH);
                                end
                            end else begin//测试模式，初始化中间指针
                                enb <= 1<<midd_cnt;
                                addr_m <= midd_ptr +offset << (midd_cnt*ADDR_WIDTH);
                            end
                        end
                    end
                endcase
            end
        end

        always@(posedge clk) begin
            if(sclr) begin
                video_data_out <= 0;
            end else if(ce) begin
                case(next_state_d3)
                    LEFT:begin
                        video_data_out <= dout_m[midd_cnt_d3*VIDEO_DATA_WIDTH +VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH];//dout_m[17:0];
                    end
                    MIDDLE:begin
                        video_data_out <= dout_m[midd_cnt_d3*VIDEO_DATA_WIDTH +VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH];//dout_m[17:0];
                    end
                    RIGHT:begin
                        video_data_out <= dout_m[midd_cnt_d3*VIDEO_DATA_WIDTH +VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH];//dout_m[17:0];
                    end
                    default:begin
                        if((next_state_d3 == NEXT || next_state_d3 == IDLE) && sel) begin
                            video_data_out <= 0;
                        end
                    end
                endcase
            end else begin
                video_data_out <= 0;
            end
        end
    end else if(LEFT_BLOCK && NO_COLLIDE) begin
        //   send_lself #(
        always@(posedge clk) begin
            if(sclr) begin
                addr_sr <= 0;
                ena_sr  <= 0;
                addr_sl <= 0;
                ena_sl  <= 0;
                addr_m <= 0;
                enb <= 0;
            end else if(ce) begin
                case(next_state_d2)
                    LEFT:begin
                        if(next_state==MIDDLE) begin//为下一块做准备
                            enb <= 1<<midd_cnt;
                            addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end else  begin//自己边使用
                            enb  <= 1<<midd_cnt;
                            addr_m  <= side_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end
                    end
                    MIDDLE:begin
                        if(next_state  == LEFT) begin//为下一块做准备
                            enb <= 1<<midd_cnt;
                            addr_m  <= side_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end else if(next_state  == RIGHT) begin
                            ena_sr  <= 1;//侧边只有一个端口！
                            addr_sr <= side_ptr + offset;
                        end else begin//自己边使用
                            enb <= 1<<midd_cnt;
                            addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end
                    end
                    RIGHT:begin
                        if(next_state==MIDDLE) begin//为下一块做准备
                            enb <= 1<<midd_cnt;
                            addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end else begin//自己边使用
                            ena_sr  <= 1;//侧边只有一个端口！
                            addr_sr <=  side_ptr + offset;// + offset <<(midd_cnt*ADDR_WIDTH);
                        end
                    end
                    default: begin
                        //只提前2clk周期初始化，低功耗考虑
                        if((col_cnt  == next_gate) || (col_cnt  == 0 && next_state_d2 != IDLE)) begin
                            if(mode) begin//正常模式，初始化侧边指针
                                if(!output_dir) begin//从左到右，初始化左边指针,
                                    if(next_state  == MIDDLE) begin
                                        enb <= 1<<midd_cnt;
                                        addr_m <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                                    end else begin
                                        enb <= 1<<midd_cnt;
                                        addr_m  <= side_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                                    end
                                end else begin //从右到左，初始化右边指针
                                    if(next_state  == MIDDLE) begin
                                        enb <= 1<<midd_cnt;
                                        addr_m <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                                    end else begin
                                        ena_sr  <= 1;
                                        addr_sr <=  side_ptr + offset;
                                    end
                                end
                            end else begin//测试模式，初始化中间指针
                                enb <= 1<<midd_cnt;
                                addr_m <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                            end
                        end
                    end
                endcase
            end
        end

        always@(posedge clk) begin
            if(sclr) begin
                video_data_out <= 0;
            end else if(ce) begin
                case(next_state_d3)
                    LEFT:begin
                        video_data_out <= dout_m[midd_cnt_d3*VIDEO_DATA_WIDTH +VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH];//dout_m[17:0];
                    end
                    //中间和右边共用
                    MIDDLE:begin
                        video_data_out <= dout_m[midd_cnt_d3*VIDEO_DATA_WIDTH +VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH];
                    end
                    RIGHT:begin//侧边只有一个端口！
                        video_data_out <= dout_sr[VIDEO_DATA_WIDTH-1'b1  -:VIDEO_DATA_WIDTH];
                    end
                    default: begin
                        if((next_state_d3 == NEXT || next_state_d3 == IDLE) && sel) begin
                            video_data_out <= 0;
                        end
                    end
                endcase
            end else begin
                video_data_out <= 0;
            end
        end
    end else if(RIGHT_BLOCK) begin
        always@(posedge clk) begin
            if(sclr) begin
                addr_sr <= 0;
                ena_sr  <= 0;
                addr_sl <= 0;
                ena_sl  <= 0;
                addr_m <= 0;
                enb <= 0;
            end else if(ce) begin
                case(next_state_d2)
                    LEFT:begin
                        if(next_state==MIDDLE) begin//为下一块做准备
                            enb    <= 1<<midd_cnt;
                            addr_m <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end else begin//自己边使用
                            ena_sl  <= 1;//侧边只有一个端口！
                            addr_sl <=  side_ptr + offset;// + offset <<(midd_cnt*ADDR_WIDTH);
                        end
                    end
                    MIDDLE:begin
                        if(next_state  == RIGHT) begin//为下一块做准备
                            enb    <= 1<<midd_cnt;
                            addr_m <= side_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end else if(next_state  == LEFT) begin
                            ena_sl  <= 1;//侧边只有一个端口！
                            addr_sl <=  side_ptr + offset;
                        end else begin//自己边使用
                            enb    <= 1<<midd_cnt;
                            addr_m <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end
                    end
                    RIGHT:begin
                        if(next_state==MIDDLE) begin//为下一块做准备
                            enb    <= 1<<midd_cnt;
                            addr_m <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end else  begin//自己边使用
                            enb    <= 1<<midd_cnt;
                            addr_m <= side_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end
                    end
                    default: begin
                        //只提前2clk周期初始化，低功耗考虑
                        if((col_cnt  == next_gate) || (col_cnt  == 0 && next_state_d2 != IDLE)) begin
                            if(mode) begin//正常模式，初始化侧边指针
                                if(!output_dir) begin//从左到右，初始化左边指针
                                    if(next_state  == MIDDLE) begin
                                        enb <= 1<<midd_cnt;
                                        addr_m <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                                    end else begin
                                        ena_sl  <= 1;
                                        addr_sl <=  side_ptr + offset;
                                    end
                                end else begin //从右到左，初始化右边指针
                                    if(next_state  == MIDDLE) begin
                                        enb <= 1<<midd_cnt;
                                        addr_m <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                                    end else begin
                                        enb <= 1<<midd_cnt;
                                        addr_m <= side_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                                    end
                                end
                            end else begin//测试模式，初始化中间指针
                                enb <= 1<<midd_cnt;
                                addr_m <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                            end
                        end else begin
                        end
                    end
                endcase
            end
        end

        always@(posedge clk) begin
            if(sclr) begin
                video_data_out <= 0;
            end else
            if(ce) begin
                case(next_state_d3)
                    LEFT:begin//侧边只有一个端口！
                        video_data_out <= dout_sl[VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH];
                    end
                    //中间和右边共用
                    MIDDLE:begin
                        video_data_out <= dout_m[midd_cnt_d3*VIDEO_DATA_WIDTH +VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH];
                    end
                    RIGHT:begin
                        video_data_out <= dout_m[midd_cnt_d3*VIDEO_DATA_WIDTH +VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH];
                    end
                    default: begin
                        if((next_state_d3 == NEXT || next_state_d3 == IDLE) && sel) begin
                            video_data_out <= 0;
                        end
                    end
                endcase
            end else begin
                video_data_out <= 0;
            end
        end
    end else if(MIDD_BLOCK) begin
        always@(posedge clk) begin
            if(sclr) begin
                addr_sr <= 0;
                ena_sr  <= 0;
                addr_sl <= 0;
                ena_sl  <= 0;
                addr_m <= 0;
                enb <= 0;
            end else if(ce) begin
                case(next_state_d2)
                    LEFT:begin
                        if(next_state==MIDDLE) begin//为下一块做准备
                            enb     <= 1<<midd_cnt;
                            addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end else begin//自己边使用
                            ena_sl  <= 1;
                            addr_sl <=  side_ptr + offset;
                        end
                    end
                    MIDDLE:begin
                        if(next_state  == LEFT) begin//为下一块做准备
                            ena_sl  <= 1;
                            addr_sl <=  side_ptr + offset;
                        end else if(next_state  == RIGHT) begin
                            ena_sr   <= 1;
                            addr_sr  <=  side_ptr + offset;
                        end else  begin//自己边使用
                            enb     <= 1<<midd_cnt;
                            addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end
                    end
                    RIGHT:begin
                        if(next_state==MIDDLE) begin//为下一块做准备
                            enb     <= 1<<midd_cnt;
                            addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end else begin//自己边使用
                            ena_sr  <= 1;
                            addr_sr <=  side_ptr + offset;
                        end
                    end
                    default: begin
                        //只提前2clk周期初始化，低功耗考虑
                        if((col_cnt  == next_gate) || (col_cnt  == 0 && next_state_d2 != IDLE)) begin
                            if(mode) begin//正常模式，初始化侧边指针
                                if(!output_dir) begin//从左到右，初始化左边指针
                                    if(next_state  == MIDDLE) begin
                                        enb     <= 1<<midd_cnt;
                                        addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                                    end else begin
                                        ena_sl  <= 1;
                                        addr_sl <=  side_ptr + offset;
                                    end
                                end else begin //从右到左，初始化右边指针
                                    if(next_state  == MIDDLE) begin
                                        enb     <= 1<<midd_cnt;
                                        addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                                    end else begin
                                        ena_sr  <= 1;
                                        addr_sr <=  side_ptr + offset;
                                    end
                                end
                            end else begin//测试模式，初始化中间指针
                                enb     <= 1<<midd_cnt;
                                addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                            end
                        end
                    end
                endcase
            end
        end

        always@(posedge clk) begin
            if(sclr) begin
                video_data_out <= 0;
            end else if(ce) begin
                case(next_state_d3)
                    LEFT:begin
                        video_data_out <= dout_sl[VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH];//dout_m[17:0];
                    end
                    //中间和右边共用
                    MIDDLE:begin
                        video_data_out <= dout_m[midd_cnt_d3*VIDEO_DATA_WIDTH +VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH];
                    end
                    RIGHT:begin
                        video_data_out <= dout_sr[VIDEO_DATA_WIDTH-1'b1  -:VIDEO_DATA_WIDTH];
                    end
                    default: begin
                        if((next_state_d3 == NEXT || next_state_d3 == IDLE) && sel) begin
                            video_data_out <= 0;
                        end
                    end
                endcase
            end else begin
                video_data_out <= 0;
            end
        end
    end else if(LEFT_BLOCK && !NO_COLLIDE)begin
        always@(posedge clk) begin
            if(sclr) begin
                addr_sr <= 0;
                ena_sr  <= 0;
                addr_sl <= 0;
                ena_sl  <= 0;
                addr_m <= 0;
                enb <= 0;
            end else if(ce) begin
                case(next_state_d2)
                    LEFT:begin
                        if(next_state==MIDDLE) begin//为下一块做准备
                            enb     <= 1<<midd_cnt;
                            addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end else begin//自己边使用
                            ena_sl  <= 1;
                            addr_sl <=  side_ptr + offset;
                        end
                    end
                    MIDDLE:begin
                        if(next_state  == LEFT) begin//为下一块做准备
                            ena_sl  <= 1;
                            addr_sl <=  side_ptr + offset;
                        end else if(next_state  == RIGHT) begin
                            ena_sr   <= 1;
                            addr_sr  <=  side_ptr + offset;
                        end else  begin//自己边使用
                            enb     <= 1<<midd_cnt;
                            addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end
                    end
                    RIGHT:begin
                        if(next_state==MIDDLE) begin//为下一块做准备
                            enb     <= 1<<midd_cnt;
                            addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                        end else begin//自己边使用
                            ena_sr  <= 1;
                            addr_sr <=  side_ptr + offset;
                        end
                    end
                    default: begin
                        //只提前2clk周期初始化，低功耗考虑
                        if((col_cnt  == next_gate) || (col_cnt  == 0 && next_state_d2 != IDLE)) begin
                            if(mode) begin//正常模式，初始化侧边指针
                                if(!output_dir) begin//从左到右，初始化左边指针
                                    if(next_state  == MIDDLE) begin
                                        enb     <= 1<<midd_cnt;
                                        addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                                    end else begin
                                        ena_sl  <= 1;
                                        addr_sl <=  side_ptr + offset;
                                    end
                                end else begin //从右到左，初始化右边指针
                                    if(next_state  == MIDDLE) begin
                                        enb     <= 1<<midd_cnt;
                                        addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                                    end else begin
                                        ena_sr  <= 1;
                                        addr_sr <=  side_ptr + offset;
                                    end
                                end
                            end else begin//测试模式，初始化中间指针
                                enb     <= 1<<midd_cnt;
                                addr_m  <= midd_ptr + offset <<(midd_cnt*ADDR_WIDTH);
                            end
                        end
                    end
                endcase
            end
        end

        always@(posedge clk) begin
            if(sclr) begin
                video_data_out <= 0;
            end else if(ce) begin
                case(next_state_d3)
                    LEFT:begin
                        video_data_out <= dout_sl[VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH];//dout_m[17:0];
                    end
                    //中间和右边共用
                    MIDDLE:begin
                        video_data_out <= dout_m[midd_cnt_d3*VIDEO_DATA_WIDTH +VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH];
                    end
                    RIGHT:begin
                        video_data_out <= dout_sr[VIDEO_DATA_WIDTH-1'b1  -:VIDEO_DATA_WIDTH];
                    end
                    default: begin
                        if((next_state_d3 == NEXT || next_state_d3 == IDLE) && sel) begin
                            video_data_out <= 0;
                        end
                    end
                endcase
            end else begin
                video_data_out <= 0;
            end
        end
    end
endgenerate

//  The following function calculates the address width based on specified RAM depth
function integer clogb2;
    input integer depth;
    for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
endfunction


endmodule



