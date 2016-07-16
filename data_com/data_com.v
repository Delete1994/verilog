//==================================================================================================
//  Copyright	  : LVIT
//	Filename      : data_com.v
//	Description   :
//  Date	      : 最后代码更新时间
//  Author        : PanShen
//  History		  ：
//
//  Rev	0.1       :	这里填写每个版本的更新内容
//	Rev	0.2       :	这里填写每个版本的更新内容
//	Rev	1.0       : 这里注意1.0版本是正式版本，所以目前我们都是0.x版本
//==================================================================================================
说明：版本说明我们只需要在top文件即这里的data_com中描述就可以，子文件不需要描述

//下面的注释是子文件的注释内容
//==================================================================================================
//  Copyright	  : 写我们公司的名字（重庆宜时宜景公司）
//	Filename      : data_com.v
//	Description   : 描述当前文件的相关功能介绍
//  Date	      : 最后代码更新时间
//  Author        : PanShen
//==================================================================================================
`timescale 1ns/1ps

// `define  DEBUG_MODE

`ifdef DEBUG_MODE

    module data_com (
        sclr,
        ce,
        clk,
        ch_clk,
        hblank_in,
        vblank_in,
        active_video_in,
        video_data_in,

        hblank_out,
        vblank_out,
        active_video_out,
        video_data_out,
        mode,
        sel,

        row_start,
        row_end,
        col_start,
        col_end,
//DEBUG_MODE singal
        row_less,
        col_less,
        row_err,
        col_err,
        row_over,
        col_over,
        vblank_in_error,
        depth_err,
        width_err
    );
`else

    module data_com (
        sclr,
        ce,
        clk,
        ch_clk,
        hblank_in,
        vblank_in,
        active_video_in,
        video_data_in,

        hblank_out,
        vblank_out,
        active_video_out,
        video_data_out,
        mode,
        sel,

        row_start,
        row_end,
        col_start,
        col_end
    );
`endif

parameter CHANNEL_IN_NUM   = 8;       //输入数据块数量2^6 == 63
parameter CHANNEL_OUT_NUM  = 1;       //输出数据块数量
parameter VIDEO_DATA_WIDTH = 18;      //视频数据信号宽度
parameter RAM_DEPTH        = 10;     //行缓存ram深度
parameter TIMING_CNT_WIDTH = 10;      //行、列计数器信号宽度
parameter OVERLAP_WIDTH    = 1;       //输出数据块交叠量
parameter TOP_BOTTOM_SEL   = 1'd0;    //输入数据块由上、下部分组成标识
parameter HEAD_DIRECTION   = 1'd0;    //抽头方向0全左,1全右,2对半分
parameter FRAME_RAM_EN     = 1'd0;    //帧缓存使能
parameter OUTPUT_DIRECTION = 0;       //输入数据块的读出方向
//一个发送块包含多少个输入块，输出计数器是输入的多少倍
localparam TIMES           = CHANNEL_IN_NUM/CHANNEL_OUT_NUM;
//根据RAM深度决定RAM操作的地址宽度
localparam ADDR_WIDTH      = clogb2(RAM_DEPTH-1);
//因为是两个RAM所以宽度乘以2



//DEBUG_MODE 信号定义
`ifdef  DEBUG_MODE

// vblank_pos vblank_neg , hblank_pos,由于同时变化，故只测量ch0
reg                                              vblank_in_d1;
reg                                              hblank_in_d1;

wire                                             vblank_pos;
wire                                             vblank_neg;
wire                                             hblank_pos;

output                                           row_less;
output                                           col_less;
output                                           row_err;
output                                           col_err;
output                                           row_over;
output                                           col_over;
output                                           vblank_in_error;
output                                           depth_err;
output                                           width_err;

reg                                              vblank_in_error;
reg                                              depth_err;

wire  [CHANNEL_IN_NUM*TIMING_CNT_WIDTH-1:0]      col_cnt;
wire  [CHANNEL_IN_NUM*TIMING_CNT_WIDTH-1:0]      row_cnt;

`endif

input                                            clk;    // Clock
input                                            sclr;
input                                            ce; // Clock Enable
input                                            ch_clk;
input [CHANNEL_IN_NUM-1:0]                       hblank_in;
input [CHANNEL_IN_NUM-1:0]                       vblank_in;
input [CHANNEL_IN_NUM-1:0]                       active_video_in;
input [CHANNEL_IN_NUM*VIDEO_DATA_WIDTH-1:0]      video_data_in;
input                                            mode;
input                                            sel;

input [TIMING_CNT_WIDTH-1:0]                     row_start;
input [TIMING_CNT_WIDTH-1:0]                     row_end;
input [TIMING_CNT_WIDTH-1:0]                     col_start;
input [TIMING_CNT_WIDTH-1:0]                     col_end;

output [CHANNEL_OUT_NUM-1:0]                     hblank_out;
output [CHANNEL_OUT_NUM-1:0]                     vblank_out;
output [CHANNEL_OUT_NUM-1:0]                     active_video_out;
output [CHANNEL_OUT_NUM*VIDEO_DATA_WIDTH-1:0]    video_data_out;

reg    [CHANNEL_OUT_NUM*VIDEO_DATA_WIDTH-1:0]    video_data_out;
reg    [6:0]                                     ch;

//send -->receive
wire  [CHANNEL_IN_NUM*TIMING_CNT_WIDTH-1:0]      col_max;       //hblank_in一行最大值，包括高电平区
wire  [CHANNEL_IN_NUM*TIMING_CNT_WIDTH-1:0]      row_max;       //行数，测试模式用
wire  [CHANNEL_IN_NUM*TIMING_CNT_WIDTH-1:0]      hblank_low;    //hblank_in低电平时钟数，测试模式使用
wire  [CHANNEL_IN_NUM-1:0]                       send_start;    //receive告诉send开始发数据
//写RAM信号连接
wire  [CHANNEL_IN_NUM*ADDR_WIDTH-1'b1:0]         wr_addr1;       //接收指针，ram0使用
wire  [CHANNEL_IN_NUM*ADDR_WIDTH-1'b1:0]         wr_addr2;      //发送指针，ram1使用
wire  [CHANNEL_IN_NUM-1:0]                       pp_flagw;
wire  [CHANNEL_IN_NUM-1:0]                       pp_flagr;
wire  [CHANNEL_IN_NUM-1:0]                       effect_reigon;
//RAM块连接信号
// 左
wire  [CHANNEL_IN_NUM*ADDR_WIDTH -1:0]           addra;
wire  [CHANNEL_IN_NUM-1:0]                       ena;           //ena1读使能
wire  [CHANNEL_IN_NUM*VIDEO_DATA_WIDTH-1:0]      douta;
// 中
wire  [CHANNEL_IN_NUM*ADDR_WIDTH -1:0]           addrb;
wire  [CHANNEL_IN_NUM-1:0]                       enb;           //enb读使能（只读）
wire  [CHANNEL_IN_NUM*VIDEO_DATA_WIDTH-1:0]      doutb;

wire  [CHANNEL_IN_NUM*ADDR_WIDTH -1:0]           addrb1;
wire  [CHANNEL_IN_NUM-1:0]                       enb1;          //enb读使能（只读）switch
// 右
wire  [CHANNEL_IN_NUM*ADDR_WIDTH -1:0]           addrb2;
wire  [CHANNEL_IN_NUM-1:0]                       enb2;          //enb读使能（只读）

wire  [CHANNEL_IN_NUM*ADDR_WIDTH -1:0]           addrb3;
wire  [CHANNEL_IN_NUM-1:0]                       enb3;          //enb读使能（只读）

wire  [CHANNEL_OUT_NUM*VIDEO_DATA_WIDTH-1:0]     video_data_out1;
wire  [CHANNEL_OUT_NUM-1:0]                      switch;        //通道切换

`ifdef DEBUG_MODE

generate
    genvar i;
    for (i = 0; i < CHANNEL_IN_NUM; i=i+1) begin : i_rec_f
    receive #(
            .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
            .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
            .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
            .RAM_DEPTH(RAM_DEPTH),
            .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
            .OVERLAP_WIDTH(OVERLAP_WIDTH),
            .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
            .HEAD_DIRECTION(HEAD_DIRECTION),
            .FRAME_RAM_EN(FRAME_RAM_EN)
        ) rec (
            .channel         (i),
            .sclr            (sclr),
            .ce              (ce),
            .mode            (mode),
            .ch_clk          (ch_clk),
            .clk             (clk),

            .hblank_in       (hblank_in[i]),
            .vblank_in       (vblank_in[i]),
            .active_video_in (active_video_in[i]),

            .row_start       (row_start),
            .row_end         (row_end),
            .col_start       (col_start),
            .col_end         (col_end),
            //to data save
            .wr_addr1         (wr_addr1[i*ADDR_WIDTH+ADDR_WIDTH-1 -:ADDR_WIDTH]),
            .wr_addr2        (wr_addr2[i*ADDR_WIDTH+ADDR_WIDTH-1 -:ADDR_WIDTH]),
            .pp_flagw        (pp_flagw[i]),
            .pp_flagr        (pp_flagr[i]),
            .effect_reigon   (effect_reigon[i]),
            //to send
            .send_start      (send_start[i]),//receive --> send
            .col_max         (col_max[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH]),//receive --> send
            .row_max         (row_max[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH]),//receive --> send
            //for DEBUG_MODE
            .col_cnt         (col_cnt[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH]),//receive --> send
            .row_cnt         (row_cnt[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH]),//receive --> send

            .hblank_low      (hblank_low[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH]) //receive --> send
        );
    end
endgenerate

`else

generate
    genvar i;
    for (i = 0; i < CHANNEL_IN_NUM; i=i+1) begin : i_rec_f
    receive #(
            .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
            .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
            .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
            .RAM_DEPTH(RAM_DEPTH),
            .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
            .OVERLAP_WIDTH(OVERLAP_WIDTH),
            .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
            .HEAD_DIRECTION(HEAD_DIRECTION),
            .FRAME_RAM_EN(FRAME_RAM_EN)
        ) rec (
            .channel         (i),
            .sclr            (sclr),
            .ce              (ce),
            .mode            (mode),
            .ch_clk          (ch_clk),
            .clk             (clk),

            .hblank_in       (hblank_in[i]),
            .vblank_in       (vblank_in[i]),
            .active_video_in (active_video_in[i]),

            .row_start       (row_start),
            .row_end         (row_end),
            .col_start       (col_start),
            .col_end         (col_end),
            //to data save
            .wr_addr1         (wr_addr1[i*ADDR_WIDTH+ADDR_WIDTH-1 -:ADDR_WIDTH]),
            .wr_addr2        (wr_addr2[i*ADDR_WIDTH+ADDR_WIDTH-1 -:ADDR_WIDTH]),
            .pp_flagw        (pp_flagw[i]),
            .pp_flagr        (pp_flagr[i]),
            .effect_reigon   (effect_reigon[i]),
            //to send
            .send_start      (send_start[i]),//receive --> send
            .col_max         (col_max[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH]),//receive --> send
            .row_max         (row_max[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH]),//receive --> send
            .hblank_low      (hblank_low[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH]) //receive --> send
        );
    end
endgenerate

`endif


//RAM例化
generate
    genvar k;
    for (k = 0; k < CHANNEL_IN_NUM; k=k+1) begin : save_f
        data_save #(
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMES(TIMES),
                .RAM_DEPTH(RAM_DEPTH)
            ) i_save (
                .clk           (clk),
                .ch_clk        (ch_clk),
                .sclr          (sclr),
                .ce              (ce),
                .video_data_in (video_data_in[k*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                //from receive,for write
                .wr_addr1       (wr_addr1[k*ADDR_WIDTH+ADDR_WIDTH-1 -:ADDR_WIDTH]),
                .wr_addr2      (wr_addr2[k*ADDR_WIDTH+ADDR_WIDTH-1 -:ADDR_WIDTH]),
                .pp_flagw      (pp_flagw[k]),
                .pp_flagr      (pp_flagr[k]),
                .effect_reigon (effect_reigon[k]),
                //from send, for read
                .addra_s       (addra[k*ADDR_WIDTH+ADDR_WIDTH-1 -:ADDR_WIDTH]),
                .addrb_s       (addrb[k*ADDR_WIDTH+ADDR_WIDTH-1 -:ADDR_WIDTH]),
                .douta_s       (douta[k*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .doutb_s       (doutb[k*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_s         (ena[k]),
                .enb_s         (enb[k])
            );
    end
endgenerate


/*
左：port―a ，中：port -b 右：port-b1
此generate未考虑行交叠！
*/
generate
    genvar j;
    //此时不会存在地址冲突问题，地址可直接用porta,portb
    //没有中间输出块不会冲突,不含只有一个块的中间块地址不会冲突
    if((CHANNEL_IN_NUM != CHANNEL_OUT_NUM )|| (!TOP_BOTTOM_SEL &&  CHANNEL_OUT_NUM <= 2) || (TOP_BOTTOM_SEL && CHANNEL_OUT_NUM <= 4)) begin
        for (j = 0; j < CHANNEL_OUT_NUM; j=j+1) begin : i_send_f
            //两行排列，两个输出块,一行排列，一个输出块
            if((CHANNEL_OUT_NUM == 1) || (TOP_BOTTOM_SEL && CHANNEL_OUT_NUM == 2))begin
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) lr (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),
                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),

                .addr_m           (addrb[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_m           (doutb[(j+1)*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH*TIMES]),
                .enb              (enb[(j+1)*TIMES-1 -:TIMES]),

                .addr_sl          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sl          (0),
                .ena_sl           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .addr_sr          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sr          (0),
                .ena_sr           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );


            //左上，左边填充自己，右边填充下一个块 == 一行排列的，多块输出，最左边
            //左下，左边填充自己，右边填充上一个块
            //右上，右边填充自己，左边填充上一个块 == 一行排列，多块输出，最右边
            //右下，右边填充自己，右边填充下一个块
            //两行排列，多块输出,左上
            end else if((TOP_BOTTOM_SEL==1 &&  j == 0) ||  //左上
                        (!TOP_BOTTOM_SEL && j == 0)) begin //一行最左边
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) ul (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),

                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),

                .addr_m           (addrb[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_m           (doutb[(j+1)*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH*TIMES]),
                .enb              (enb[(j+1)*TIMES-1 -:TIMES]),

                //左上，左边填充自己，右边填充下一个块 == 一行排列的，多块输出，最左边
                .addr_sr          (addra[(j+1)*TIMES*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sr          (douta[(j+1)*TIMES*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[(j+1)*TIMES -:1]),

                .addr_sl          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sl          (0),
                .ena_sl           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );

            //两行排列，多块输出,左下
            end else if(TOP_BOTTOM_SEL && j == CHANNEL_OUT_NUM-1) begin
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) dl (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),

                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),
                // j=0
                .addr_m           (addrb[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_m           (doutb[(j+1)*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH*TIMES]),
                .enb              (enb[(j+1)*TIMES-1 -:TIMES]),

                .addr_sl          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sl          (0),
                .ena_sl           (enb3[(j+1)*TIMES-1 -:TIMES]),
                //左下，左边填充自己，右边填充上一个块
                .addr_sr          (addra[j*TIMES*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sr          (douta[j*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[j*TIMES - 1 -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low          (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );

            //两行排列，多块输出,右上,最右
            end else if((TOP_BOTTOM_SEL && j == (CHANNEL_OUT_NUM>>1)-1) ||
                        (!TOP_BOTTOM_SEL && j == CHANNEL_OUT_NUM-1) ) begin
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) ur (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),

                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),
                // j=0
                .addr_m           (addrb[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_m           (doutb[(j+1)*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH*TIMES]),
                .enb              (enb[(j+1)*TIMES-1 -:TIMES]),
                //右上，右边填充自己，左边填充上一个块 == 一行排列，多块输出，最右边
                .addr_sl           (addra[j*TIMES*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sl           (douta[j*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl            (ena[j*TIMES - 1 -:1]),

                .addr_sr          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sr          (0),
                .ena_sr           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low          (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );
            //两行排列，多块输出,右下
            end else if(TOP_BOTTOM_SEL && j == CHANNEL_OUT_NUM>>1) begin
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) dr (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),

                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),
                // j=0
                .addr_m           (addrb[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_m           (doutb[(j+1)*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH*TIMES]),
                .enb              (enb[(j+1)*TIMES-1 -:TIMES]),
                //右下，右边填充自己，左边填充下一个块
                .addr_sl           (addra[(j+1)*TIMES*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sl           (douta[(j+1)*TIMES*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl            (ena[(j+1)*TIMES -:1]),

                .addr_sr          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sr          (0),
                .ena_sr           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low          (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );
            //剩余的，在中间的，
            //上一排，从左到右递增，左边上一个块，右边下一个块
            //下一排，从左到右递减，左边下一个块，右边上一个块
            end else if((!TOP_BOTTOM_SEL && (0 < j && j < CHANNEL_OUT_NUM-1)) ||//一排中间
                        (TOP_BOTTOM_SEL && (0 < j && j < CHANNEL_OUT_NUM/2 -1))) begin//两排上排中间
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) um (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),

                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),
                //TIMES=1
                .addr_m           (addrb[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_m           (doutb[(j+1)*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH*TIMES]),
                .enb              (enb[(j+1)*TIMES-1 -:TIMES]),

                //上一排，从左到右递增，左边上一个块，右边下一个块
                .addr_sl          (addra[j*TIMES*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sl          (douta[j*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (ena[j*TIMES -1 -:1]),//ched!
                //注意，无times
                .addr_sr          (addra[(j+1)*TIMES*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sr          (douta[(j+1)*TIMES*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[(j+1)*TIMES -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low          (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );
            end else if(TOP_BOTTOM_SEL && (CHANNEL_OUT_NUM/2 < j && j < CHANNEL_OUT_NUM-1 )) begin//两排下排中间
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) dm (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),

                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),
                //TIMES=1
                .addr_m           (addrb[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_m           (doutb[(j+1)*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH*TIMES]),
                .enb              (enb[(j+1)*TIMES-1 -:TIMES]),

                //下一排，从左到右递减，左边下一个块，右边上一个块
                .addr_sl          (addra[(j+1)*TIMES*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sl          (douta[(j+1)*TIMES*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (ena[(j+1)*TIMES -:1]),

                .addr_sr          (addra[j*TIMES*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sr          (douta[j*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[j*TIMES -1 -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low          (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );
            end
        end
    end else begin
    //中间块地址可能会冲突 TIMES == 1
        for (j = 0; j < CHANNEL_OUT_NUM; j=j+1) begin : i_send_f1
            //左上，左边填充自己，右边填充下一个块 == 一行排列的，多块输出，最左边
            //左下，左边填充自己，右边填充上一个块
            //右上，右边填充自己，左边填充上一个块 == 一行排列，多块输出，最右边
            //右下，右边填充自己，右边填充下一个块
            //两行排列，多块输出,左上 TIMES == 1
            if((TOP_BOTTOM_SEL &&  j == 0) ||  //左上
               (!TOP_BOTTOM_SEL && j == 0)) begin //一行最左边
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) ul (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),

                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),

                .addr_m           (addrb1[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),
                .dout_m           (doutb[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .enb              (enb1[j -: 1]),

                .addr_sl          (addra[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),//a0
                .dout_sl          (douta[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (ena[j -: 1]),
                //左上，左边填充自己，右边填充下一个块 == 一行排列的，多块输出，最左边
                .addr_sr          (addra[(j+1)*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),//a1
                .dout_sr          (douta[(j+1)*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[(j+1) -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low          (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );

            //两行排列，多块输出,左下
            end else if(TOP_BOTTOM_SEL && j == CHANNEL_OUT_NUM-1) begin
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) dl (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),

                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),
                // j=0
                .addr_m           (addrb1[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),
                .dout_m           (doutb[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .enb              (enb1[j -: 1]),
                //左下，左边填充自己，右边填充上一个块
                .addr_sl          (addra[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),//a7
                .dout_sl          (douta[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (ena[j -: 1]),

                .addr_sr          (addra[j*ADDR_WIDTH -1-:ADDR_WIDTH]),//a6
                .dout_sr          (douta[j*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[j - 1 -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low          (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );

            //两行排列，多块输出,右上
            end else if((TOP_BOTTOM_SEL && j == (CHANNEL_OUT_NUM>>1)-1) ||
                        (!TOP_BOTTOM_SEL && j == CHANNEL_OUT_NUM-1) ) begin
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) ur (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),

                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),
                // j=0
                .addr_m           (addrb1[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),
                .dout_m           (doutb[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .enb              (enb1[j -: 1]),
                //右上，右边填充自己，左边填充上一个块 == 一行排列，多块输出，最右边
                .addr_sl           (addrb2[j*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sl           (doutb[j*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl            (enb2[j - 1 -:1]),

                .addr_sr          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sr          (0),
                .ena_sr           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low          (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );
            //两行排列，多块输出,右下
            end else if(TOP_BOTTOM_SEL && j == CHANNEL_OUT_NUM>>1) begin
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) dr (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),

                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),
                // j=0
                .addr_m           (addrb1[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),
                .dout_m           (doutb[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .enb              (enb1[j -: 1]),
                //右下，右边填充自己，左边填充下一个块
                .addr_sl          (addrb2[(j+1)*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sl          (doutb[(j+1)*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (enb2[(j+1) -:1]),

                .addr_sr          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sr          (0),
                .ena_sr           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low          (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );
            //剩余的，在中间的，
            //上一排，从左到右递增，左边上一个块，右边下一个块
            //下一排，从左到右递减，左边下一个块，右边上一个块
            end else if((!TOP_BOTTOM_SEL && (0 < j && j < CHANNEL_OUT_NUM-1)) ||//一排中间
                        (TOP_BOTTOM_SEL && (0 < j && j < CHANNEL_OUT_NUM/2 -1))) begin//两排上排中间1 2
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) um (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),

                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),
                //TIMES=1
                .addr_m           (addrb1[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),
                .dout_m           (doutb[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .enb              (enb1[(j+1)-1 -:TIMES]),

                //上一排，从左到右递增，左边上一个块，右边下一个块
                .addr_sl          (addrb2[j*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sl          (doutb[j*VIDEO_DATA_WIDTH -1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (enb2[j -1 -: 1]),
                //注意，无times 2 4w-1 3w j=1 2 a2,a3
                .addr_sr          (addra[(j+1)*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sr          (douta[(j+1)*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[(j+1) -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low          (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );
            end else if(TOP_BOTTOM_SEL && (CHANNEL_OUT_NUM/2 < j && j < CHANNEL_OUT_NUM-1 )) begin//两排下排中间 5 6
            send #(
                .CHANNEL_IN_NUM(CHANNEL_IN_NUM),
                .CHANNEL_OUT_NUM(CHANNEL_OUT_NUM),
                .VIDEO_DATA_WIDTH(VIDEO_DATA_WIDTH),
                .TIMING_CNT_WIDTH(TIMING_CNT_WIDTH),
                .RAM_DEPTH(RAM_DEPTH),
                .OVERLAP_WIDTH(OVERLAP_WIDTH),
                .TOP_BOTTOM_SEL(TOP_BOTTOM_SEL),
                .HEAD_DIRECTION(HEAD_DIRECTION),
                .OUTPUT_DIRECTION(OUTPUT_DIRECTION),
                .FRAME_RAM_EN(FRAME_RAM_EN),
                .CH(j)
            ) dm (
                .sclr             (sclr),
                .ce               (ce),
                .clk              (clk),
                .mode             (mode),
                .sel              (sel),

                .hblank_out       (hblank_out[j]),
                .vblank_out       (vblank_out[j]),
                .active_video_out (active_video_out[j]),
                .video_data_out   (video_data_out1[j*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .switch           (switch[j]),

                .col_start        (col_start),
                .col_end          (col_end),
                .row_start        (row_start),
                .row_end          (row_end),
                //TIMES=1
                .addr_m           (addrb1[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),
                .dout_m           (doutb[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .enb              (enb1[j -: 1]),

                //下一排，从左到右递减，左边下一个块，右边上一个块
                .addr_sl          (addrb2[(j+1)*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sl          (doutb[(j+1)*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (enb2[(j+1) -:1]),
                //j=5,6 a4,a5
                .addr_sr          (addra[j*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sr          (douta[j*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[j -1 -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .hblank_low          (hblank_low[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),//一个就够了
                .send_start       (send_start[0])//一个就够了

            );
            end
        end
        //两排的
        if(TOP_BOTTOM_SEL) begin
            //2排的8 - 8w-1:5w 2w0 3w-1:0
            assign addrb = addrb1 | {addrb2[CHANNEL_IN_NUM*ADDR_WIDTH-1:(CHANNEL_IN_NUM/2+1)*ADDR_WIDTH],
                                   {ADDR_WIDTH*2{1'b0}},addrb2[(CHANNEL_IN_NUM/2-1)*ADDR_WIDTH-1:0]};
                                 // 7:5 43 2:0
            assign enb =  enb1 | {enb2[CHANNEL_IN_NUM-1:(CHANNEL_IN_NUM/2+1)],2'd0,enb2[(CHANNEL_IN_NUM/2-1)-1:0]};
        end else begin
            assign addrb = addrb1 | {{ADDR_WIDTH{1'b0}},addrb2[(CHANNEL_IN_NUM-1)*ADDR_WIDTH-1:0]};
            assign enb   = enb1 | {1'b0,enb2[CHANNEL_IN_NUM-2:0]};
        end

    end
endgenerate


//通道切换
always @(*) begin
    for (ch = 0; ch < CHANNEL_OUT_NUM; ch = ch + 1) begin
        if(switch[ch]) begin
            video_data_out[(ch + 1)*VIDEO_DATA_WIDTH -1 -: VIDEO_DATA_WIDTH] = video_data_out1[(CHANNEL_OUT_NUM-ch)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH];
        end else begin
            video_data_out[(ch + 1)*VIDEO_DATA_WIDTH -1 -: VIDEO_DATA_WIDTH] = video_data_out1[(ch + 1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH];
        end
    end
end


//  The following function calculates the address width based on specified RAM depth
function integer clogb2;
    input integer depth;
    for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
endfunction


/*
1   row_less    out 1   1：输入数据行数小于row_end - row_start； row_max < row_end - row_start
                        0：输入数据行数等于row_end – row_start。
2   col_less    out 1   1：输入数据列数小于col_end - col_start； hblank_low < col_end - col_start
                        0：输入数据列数等于col_end – col_start。
3   row_error   out 1   1：输入信号row_start > row_end；
                        0：输入信号row_start <=row_end
4   col_error   out 1   1：输入信号col_start > col_end；
                        0：输入信号col_start <=col_end。
5   row_over    out 1   1：行计数器上溢出（row_cnt全1）； row_cnt
                        0：row_cnt未溢出。
6   col_over    out 1   1：列计数器上溢出（col_cnt全1）;  col_cnt
                        0：col_cnt未溢出。
7   vblank_in_error out 1   1：vblank_in不在hblank_in上升沿变化；vblank_pos vblank_neg , hblank_pos
                        0  ：vblank_in在hblank_in上升沿变化。
8   depth_error out 1   1：RAM_DEPTH配置错误，缓存数据溢出；1 ,mode = 0; hblow > depth , 2 mode = 1 ,rowsave+1 * effect_width_i
                        0：RAM_DEPTH配置正确，足够缓存数据。
9   width_error out 1   1：TIMING_CNT_WIDTH配置错误，行列计数器溢出；row_over | col_over
                        0：TIMING_CNT_WIDTH配置正确，行列计数器未溢出。

//两行排列，缓存失能，设置保存行数
assign row_save = (TOP_BOTTOM_SEL && !FRAME_RAM_EN) ? ((OVERLAP_WIDTH-1)/2):1'b0;
(row_save+1)*
7   width_error out 1   1：TIMING_CNT_WIDTH配置错误，行列计数器溢出；
                        0：TIMING_CNT_WIDTH配置正确，行列计数器未溢出。
 */


`ifdef DEBUG_MODE

always @(posedge clk) begin
    if(sclr) begin
        hblank_in_d1 <= 0;
        vblank_in_d1 <= 0;
    end else begin
        hblank_in_d1 <= hblank_in[0];
        vblank_in_d1 <= vblank_in[0];
    end
end

assign hblank_pos = !hblank_in_d1 && hblank_in[0];
assign vblank_pos = !vblank_in_d1 && vblank_in[0];
assign vblank_neg = vblank_in_d1 && !vblank_in[0];

always @(*) begin
    if(mode) begin
        if(TOP_BOTTOM_SEL && !FRAME_RAM_EN) begin//hang((OVERLAP_WIDTH-1)/2)
            if((col_end - col_start + 1'b1)*((OVERLAP_WIDTH-1)/2) > RAM_DEPTH) begin
                depth_err = 1'b1;
            end else begin
                depth_err = 1'b0;
            end
        end else begin
            // if((col_end - col_start + 1'b1) > RAM_DEPTH) begin
            if((col_end - col_start) > RAM_DEPTH - 1) begin
                depth_err = 1'b1;
            end else begin
                depth_err = 1'b0;
            end
        end
    end else begin
        if((col_end - col_start) > RAM_DEPTH - 1) begin
            depth_err = 1'b1;
        end else begin
            depth_err = 1'b0;
        end
    end
end

always @(*) begin
    if((vblank_pos || vblank_neg)) begin
        if(hblank_pos) begin
            vblank_in_error = 1'b0;
        end else begin
            vblank_in_error = 1'b1;
        end
    end else begin
        vblank_in_error = 1'b0;
    end
end

assign row_less = row_max[TIMING_CNT_WIDTH-1:0] < col_end - col_start ? 1'b1 : 1'b0;
assign col_less = hblank_low < col_end - col_start ? 1'b1 : 1'b0;
assign row_err = row_start > row_end ? 1'b1 : 1'b0;
assign col_err = col_start > col_end ? 1'b1 : 1'b0;
assign row_over = row_cnt[TIMING_CNT_WIDTH-1:0] == {TIMING_CNT_WIDTH{1'b1}} ? 1'b1 : 1'b0;
assign col_over = col_cnt[TIMING_CNT_WIDTH-1:0] == {TIMING_CNT_WIDTH{1'b1}} ? 1'b1 : 1'b0;
// assign vblank_in_error = (vblank_pos || vblank_neg) == hblank_pos ? 1'b0 : 1'b1;
assign width_err = col_over | row_over;



`endif


endmodule // data_com
