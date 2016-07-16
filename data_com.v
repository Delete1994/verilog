//==================================================================================================
//  Company       : LVIT Ltd.
//  Filename      : data_com.v
//  Description   : ���ݺϳ�ģ�鶥��
//  Date          : 2016��7��12�� 15:12:56
//  Author        : PanShen
//  History       ��
//
//  Rev 0.1       : ���DEBUGģʽ���ź�
//==================================================================================================

`timescale 1ns/1ps

// `define  DEBUG_MODE


module data_com (
`ifdef
//DEBUG_MODE singal
    row_less,
    col_less,
    row_err,
    col_err,
    row_over,
    col_over,
    vblank_in_error,
    depth_err,
    width_err,
`endif
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


parameter CHANNEL_IN_NUM   = 8;       //�������ݿ�����2^6 == 63
parameter CHANNEL_OUT_NUM  = 1;       //������ݿ�����
parameter VIDEO_DATA_WIDTH = 18;      //��Ƶ�����źſ��
parameter RAM_DEPTH        = 10;      //�л���ram���
parameter TIMING_CNT_WIDTH = 10;      //�С��м������źſ��
parameter OVERLAP_WIDTH    = 1;       //������ݿ齻����
parameter TOP_BOTTOM_SEL   = 1'd0;    //�������ݿ����ϡ��²�����ɱ�ʶ
parameter HEAD_DIRECTION   = 1'd0;    //��ͷ����0ȫ��,1ȫ��,2�԰��
parameter FRAME_RAM_EN     = 1'd0;    //֡����ʹ��
parameter OUTPUT_DIRECTION = 0;       //�������ݿ�Ķ�������

//һ�����Ϳ�������ٸ�����飬���������������Ķ��ٱ�
localparam TIMES           = CHANNEL_IN_NUM/CHANNEL_OUT_NUM;
//����RAM��Ⱦ���RAM�����ĵ�ַ���
localparam ADDR_WIDTH      = clogb2(RAM_DEPTH-1);




//DEBUG_MODE �źŶ���
`ifdef  DEBUG_MODE

// vblank_pos vblank_neg , hblank_pos,����ͬʱ�仯����ֻ����ch0
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

input                                            clk;
input                                            sclr;
input                                            ce;
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
wire  [CHANNEL_IN_NUM*TIMING_CNT_WIDTH-1:0]      col_max;       //hblank_inһ�����ֵ�������ߵ�ƽ��
wire  [CHANNEL_IN_NUM*TIMING_CNT_WIDTH-1:0]      row_max;       //����������ģʽ��
wire  [CHANNEL_IN_NUM*TIMING_CNT_WIDTH-1:0]      hblank_low;    //hblank_in�͵�ƽʱ����������ģʽʹ��
wire  [CHANNEL_IN_NUM-1:0]                       send_start;    //receive����send��ʼ������
//дRAM�ź�����
wire  [CHANNEL_IN_NUM*ADDR_WIDTH-1'b1:0]         wr_addr1;      //����ָ�룬ram0ʹ��
wire  [CHANNEL_IN_NUM*ADDR_WIDTH-1'b1:0]         wr_addr2;      //����ָ�룬ram1ʹ��
wire  [CHANNEL_IN_NUM-1:0]                       pp_flagw;
wire  [CHANNEL_IN_NUM-1:0]                       pp_flagr;
wire  [CHANNEL_IN_NUM-1:0]                       effect_reigon;
//RAM�������ź�
// ��
wire  [CHANNEL_IN_NUM*ADDR_WIDTH -1:0]           addra;
wire  [CHANNEL_IN_NUM-1:0]                       ena;           //ena1��ʹ��
wire  [CHANNEL_IN_NUM*VIDEO_DATA_WIDTH-1:0]      douta;
// ��
wire  [CHANNEL_IN_NUM*ADDR_WIDTH -1:0]           addrb;
wire  [CHANNEL_IN_NUM-1:0]                       enb;           //enb��ʹ�ܣ�ֻ����
wire  [CHANNEL_IN_NUM*VIDEO_DATA_WIDTH-1:0]      doutb;

wire  [CHANNEL_IN_NUM*ADDR_WIDTH -1:0]           addrb1;
wire  [CHANNEL_IN_NUM-1:0]                       enb1;          //enb��ʹ�ܣ�ֻ����switch
// ��
wire  [CHANNEL_IN_NUM*ADDR_WIDTH -1:0]           addrb2;
wire  [CHANNEL_IN_NUM-1:0]                       enb2;          //enb��ʹ�ܣ�ֻ����

wire  [CHANNEL_IN_NUM*ADDR_WIDTH -1:0]           addrb3;
wire  [CHANNEL_IN_NUM-1:0]                       enb3;          //enb��ʹ�ܣ�ֻ������ռλ�ã�

wire  [CHANNEL_OUT_NUM*VIDEO_DATA_WIDTH-1:0]     video_data_out1;//����ģ��������ݣ�switch������͵�����˿�
wire  [CHANNEL_OUT_NUM-1:0]                      switch;        //ͨ���л��ź�


//����ģ������


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
            .send_start      (send_start[i]),
            .col_max         (col_max[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH]),
            .row_max         (row_max[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH]),

        `ifdef DEBUG_MODE
            //for DEBUG_MODE
            .col_cnt         (col_cnt[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH]),
            .row_cnt         (row_cnt[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH]),
        `endif

            .hblank_low      (hblank_low[i*TIMING_CNT_WIDTH+TIMING_CNT_WIDTH-1 -:TIMING_CNT_WIDTH])
        );
    end
endgenerate



//RAM����
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


//����ģ������
/*
ע��
������lr��leftside and  rightside fill own channel data һ����������Ҿ�����Լ�
      ul: upper left   ���Ϸ����ݣ��������Լ����ұ������һ���� ����һ������������ͬ��
      ur: upper right  ���Ϸ����ݣ��ұ�����Լ�����������һ���� ����һ������������ͬ��
      dl: down left    ���·����ݣ��������Լ����ұ������һ����
      dr��down right   ���·����ݣ��ұ�����Լ�����������һ����
      um: upper middle ���Ϸ����ݣ���������һ���飬�ұ������һ����
      dm: down middle  ���·����ݣ���������һ���飬�ұ������һ����
��ע����8����8����������������Ϊ����CHANNEL_OUT_NUM = 8,j = 0-7
    j = 0 ʱ���� ul ; j = 1,2 um; j = 3, ur
    j = 7        dl ; j = 6,5 dm; j = 4, dr
    j = n ʱ����һ�����������ͨ��n + 1,��һ�����������ͨ��n - 1,�Լ��鼴Ϊ����ͨ��n���������ݿ���
*/
generate
    genvar j;
    //��ʱ������ڵ�ַ��ͻ���⣬��ַ��ֱ����porta,portb
    //û���м�����鲻���ͻ,����ֻ��һ������м���ַ�����ͻ
    if((CHANNEL_IN_NUM != CHANNEL_OUT_NUM )|| (!TOP_BOTTOM_SEL &&  CHANNEL_OUT_NUM <= 2) || (TOP_BOTTOM_SEL && CHANNEL_OUT_NUM <= 4)) begin
        for (j = 0; j < CHANNEL_OUT_NUM; j=j+1) begin : i_send_f
            //�������У���������飻һ�����У�һ������飬������䲿�־�Ϊ�������ݿ龵�����
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
                //addr3ռλʹ��,���������ң���ͬ
                //��Ϊ�������ֻ��Ҫһ��b�˿ڼ���
                .addr_sl          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sl          ({VIDEO_DATA_WIDTH{1'd0}}),
                .ena_sl           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .addr_sr          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sr          ({VIDEO_DATA_WIDTH{1'd0}}),
                .ena_sr           (enb3[(j+1)*TIMES-1 -:TIMES]),

                //���������ź�����receiveģ�飬������CHANNEL_IN_NUM���������ݾ���ͬ����ֻ����һ�鼴�ɣ���ͬ
                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );


            //���ϣ��������Լ����ұ������һ���� == һ�����еģ��������������
            //���£��������Լ����ұ������һ����
            //���ϣ��ұ�����Լ�����������һ���� == һ�����У������������ұ�
            //���£��ұ�����Լ�����������һ����
            //�������У�������,����
            end else if((TOP_BOTTOM_SEL==1 &&  j == 0) ||  //����
                        (!TOP_BOTTOM_SEL && j == 0)) begin //һ�������
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

                //���ϣ��������Լ����ұ������һ���� == һ�����еģ��������������
                .addr_sr          (addra[(j+1)*TIMES*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sr          (douta[(j+1)*TIMES*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[(j+1)*TIMES -:1]),

                .addr_sl          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sl          ({VIDEO_DATA_WIDTH{1'd0}}),
                .ena_sl           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );

            //�������У�������,����
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

                .addr_m           (addrb[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_m           (doutb[(j+1)*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH*TIMES]),
                .enb              (enb[(j+1)*TIMES-1 -:TIMES]),

                .addr_sl          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sl          ({VIDEO_DATA_WIDTH{1'd0}}),
                .ena_sl           (enb3[(j+1)*TIMES-1 -:TIMES]),
                //���£��������Լ����ұ������һ����
                .addr_sr          (addra[j*TIMES*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sr          (douta[j*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[j*TIMES - 1 -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );

            //�������У�������,����,����
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

                .addr_m           (addrb[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_m           (doutb[(j+1)*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH*TIMES]),
                .enb              (enb[(j+1)*TIMES-1 -:TIMES]),
                //���ϣ��ұ�����Լ�����������һ���� == һ�����У������������ұ�
                .addr_sl           (addra[j*TIMES*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sl           (douta[j*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl            (ena[j*TIMES - 1 -:1]),

                .addr_sr          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sr          ({VIDEO_DATA_WIDTH{1'd0}}),
                .ena_sr           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );
            //�������У�������,����
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

                .addr_m           (addrb[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_m           (doutb[(j+1)*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH*TIMES]),
                .enb              (enb[(j+1)*TIMES-1 -:TIMES]),
                //���£��ұ�����Լ�����������һ����
                .addr_sl           (addra[(j+1)*TIMES*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sl           (douta[(j+1)*TIMES*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl            (ena[(j+1)*TIMES -:1]),

                .addr_sr          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sr          ({VIDEO_DATA_WIDTH{1'd0}}),
                .ena_sr           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );
            //ʣ��ģ����м�ģ�
            //��һ�ţ������ҵ����������һ���飬�ұ���һ����
            //��һ�ţ������ҵݼ��������һ���飬�ұ���һ����
            end else if((!TOP_BOTTOM_SEL && (0 < j && j < CHANNEL_OUT_NUM-1)) ||        //һ���м�
                        (TOP_BOTTOM_SEL && (0 < j && j < CHANNEL_OUT_NUM/2 -1))) begin  //���������м�
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

                .addr_m           (addrb[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_m           (doutb[(j+1)*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH*TIMES]),
                .enb              (enb[(j+1)*TIMES-1 -:TIMES]),

                //��һ�ţ������ҵ����������һ���飬�ұ���һ����
                .addr_sl          (addra[j*TIMES*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sl          (douta[j*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (ena[j*TIMES -1 -:1]),

                .addr_sr          (addra[(j+1)*TIMES*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sr          (douta[(j+1)*TIMES*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[(j+1)*TIMES -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );
            end else if(TOP_BOTTOM_SEL && (CHANNEL_OUT_NUM/2 < j && j < CHANNEL_OUT_NUM-1 )) begin//���������м�
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

                .addr_m           (addrb[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_m           (doutb[(j+1)*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH*TIMES]),
                .enb              (enb[(j+1)*TIMES-1 -:TIMES]),

                //��һ�ţ������ҵݼ��������һ���飬�ұ���һ����
                .addr_sl          (addra[(j+1)*TIMES*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sl          (douta[(j+1)*TIMES*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (ena[(j+1)*TIMES -:1]),

                .addr_sr          (addra[j*TIMES*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sr          (douta[j*TIMES*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[j*TIMES -1 -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );
            end
        end
    end else begin
    //�м���ַ���ܻ��ͻ TIMES == 1
        for (j = 0; j < CHANNEL_OUT_NUM; j=j+1) begin : i_send_f1
            //���ϣ��������Լ����ұ������һ���� == һ�����еģ��������������
            //���£��������Լ����ұ������һ����
            //���ϣ��ұ�����Լ�����������һ���� == һ�����У������������ұ�
            //���£��ұ�����Լ�����������һ����
            //�������У�������,���� TIMES == 1
            if((TOP_BOTTOM_SEL &&  j == 0) ||     //����
               (!TOP_BOTTOM_SEL && j == 0)) begin //һ�������
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

                .addr_sl          (addra[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),            //a0����8�������������ã���ͬ��
                .dout_sl          (douta[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (ena[j -: 1]),
                //���ϣ��������Լ����ұ������һ���� == һ�����еģ��������������
                .addr_sr          (addra[(j+1)*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]), //a1
                .dout_sr          (douta[(j+1)*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[(j+1) -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );

            //�������У�������,����
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

                .addr_m           (addrb1[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),
                .dout_m           (doutb[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .enb              (enb1[j -: 1]),
                //���£��������Լ����ұ������һ����
                .addr_sl          (addra[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),//a7
                .dout_sl          (douta[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (ena[j -: 1]),

                .addr_sr          (addra[j*ADDR_WIDTH -1-:ADDR_WIDTH]),//a6
                .dout_sr          (douta[j*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[j - 1 -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );

            //�������У�������,����
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

                .addr_m           (addrb1[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),
                .dout_m           (doutb[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .enb              (enb1[j -: 1]),
                //���ϣ��ұ�����Լ�����������һ���� == һ�����У������������ұ�
                .addr_sl           (addrb2[j*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sl           (doutb[j*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl            (enb2[j - 1 -:1]),

                .addr_sr          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sr          ({VIDEO_DATA_WIDTH{1'd0}}),
                .ena_sr           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );
            //�������У�������,����
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

                .addr_m           (addrb1[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),
                .dout_m           (doutb[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .enb              (enb1[j -: 1]),
                //���£��ұ�����Լ�����������һ����
                .addr_sl          (addrb2[(j+1)*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sl          (doutb[(j+1)*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (enb2[(j+1) -:1]),

                .addr_sr          (addrb3[(j+1)*ADDR_WIDTH*TIMES -1 -:ADDR_WIDTH*TIMES]),
                .dout_sr          ({VIDEO_DATA_WIDTH{1'd0}}),
                .ena_sr           (enb3[(j+1)*TIMES-1 -:TIMES]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );
            //ʣ��ģ����м�ģ�
            //��һ�ţ������ҵ����������һ���飬�ұ���һ����
            //��һ�ţ������ҵݼ��������һ���飬�ұ���һ����
            end else if((!TOP_BOTTOM_SEL && (0 < j && j < CHANNEL_OUT_NUM-1)) ||        //һ���м�
                        (TOP_BOTTOM_SEL && (0 < j && j < CHANNEL_OUT_NUM/2 -1))) begin  //���������м�1 2
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

                .addr_m           (addrb1[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),
                .dout_m           (doutb[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .enb              (enb1[(j+1)-1 -:TIMES]),

                //��һ�ţ������ҵ����������һ���飬�ұ���һ����
                .addr_sl          (addrb2[j*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sl          (doutb[j*VIDEO_DATA_WIDTH -1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (enb2[j -1 -: 1]),

                .addr_sr          (addra[(j+1)*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sr          (douta[(j+1)*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[(j+1) -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );
            end else if(TOP_BOTTOM_SEL && (CHANNEL_OUT_NUM/2 < j && j < CHANNEL_OUT_NUM-1 )) begin//���������м� 5 6
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

                .addr_m           (addrb1[(j+1)*ADDR_WIDTH -1 -:ADDR_WIDTH]),
                .dout_m           (doutb[(j+1)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .enb              (enb1[j -: 1]),

                //��һ�ţ������ҵݼ��������һ���飬�ұ���һ����
                .addr_sl          (addrb2[(j+1)*ADDR_WIDTH + ADDR_WIDTH-1-:ADDR_WIDTH]),
                .dout_sl          (doutb[(j+1)*VIDEO_DATA_WIDTH + VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sl           (enb2[(j+1) -:1]),
                //j=5,6 a4,a5
                .addr_sr          (addra[j*ADDR_WIDTH -1-:ADDR_WIDTH]),
                .dout_sr          (douta[j*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH]),
                .ena_sr           (ena[j -1 -:1]),

                .row_max          (row_max[TIMING_CNT_WIDTH-1:0]),
                .hblank_low       (hblank_low[TIMING_CNT_WIDTH-1:0]),
                .col_max          (col_max[TIMING_CNT_WIDTH-1:0]),
                .send_start       (send_start[0])

            );
            end
        end
        //���ŵ�
        if(TOP_BOTTOM_SEL) begin
            //2�ŵ�8����� - 8w-1:5w 2w0 3w-1:0 ��������
            assign addrb = addrb1 | {addrb2[CHANNEL_IN_NUM*ADDR_WIDTH-1:(CHANNEL_IN_NUM/2+1)*ADDR_WIDTH],
                                   {ADDR_WIDTH*2{1'b0}},addrb2[(CHANNEL_IN_NUM/2-1)*ADDR_WIDTH-1:0]};
                                 // 7:5 43 2:0
            assign enb   =  enb1 | {enb2[CHANNEL_IN_NUM-1:(CHANNEL_IN_NUM/2+1)],2'd0,enb2[(CHANNEL_IN_NUM/2-1)-1:0]};
        end else begin
            assign addrb = addrb1 | {{ADDR_WIDTH{1'b0}},addrb2[(CHANNEL_IN_NUM-1)*ADDR_WIDTH-1:0]};
            assign enb   = enb1 | {1'b0,enb2[CHANNEL_IN_NUM-2:0]};
        end

    end
endgenerate


//ͨ���л�
always @(*) begin
    for (ch = 0; ch < CHANNEL_OUT_NUM; ch = ch + 1) begin
        if(switch[ch]) begin //�������ͨ���л������
            video_data_out[(ch + 1)*VIDEO_DATA_WIDTH -1 -: VIDEO_DATA_WIDTH] = video_data_out1[(CHANNEL_OUT_NUM-ch)*VIDEO_DATA_WIDTH-1 -:VIDEO_DATA_WIDTH];
        end else begin       //����ͨ��ֱ�����
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
1   row_less    out 1   1��������������С��row_end - row_start�� row_max < row_end - row_start
                        0������������������row_end �C row_start��
2   col_less    out 1   1��������������С��col_end - col_start�� hblank_low < col_end - col_start
                        0������������������col_end �C col_start��
3   row_error   out 1   1�������ź�row_start > row_end��
                        0�������ź�row_start <=row_end
4   col_error   out 1   1�������ź�col_start > col_end��
                        0�������ź�col_start <=col_end��
5   row_over    out 1   1���м������������row_cntȫ1���� row_cnt
                        0��row_cntδ�����
6   col_over    out 1   1���м������������col_cntȫ1��;  col_cnt
                        0��col_cntδ�����
7   vblank_in_error out 1   1��vblank_in����hblank_in�����ر仯��vblank_pos vblank_neg , hblank_pos
                        0  ��vblank_in��hblank_in�����ر仯��
8   depth_error out 1   1��RAM_DEPTH���ô��󣬻������������1 ,mode = 0; hblow > depth , 2 mode = 1 ,rowsave+1 * effect_width_i
                        0��RAM_DEPTH������ȷ���㹻�������ݡ�
9   width_error out 1   1��TIMING_CNT_WIDTH���ô������м����������row_over | col_over
                        0��TIMING_CNT_WIDTH������ȷ�����м�����δ�����

//�������У�����ʧ�ܣ����ñ�������
assign row_save = (TOP_BOTTOM_SEL && !FRAME_RAM_EN) ? ((OVERLAP_WIDTH-1)/2):1'b0;
(row_save+1)*
7   width_error out 1   1��TIMING_CNT_WIDTH���ô������м����������
                        0��TIMING_CNT_WIDTH������ȷ�����м�����δ�����
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
        if(TOP_BOTTOM_SEL && !FRAME_RAM_EN) begin
            //row save = ((OVERLAP_WIDTH-1)/2)
            if((col_end - col_start + 1'b1)*((OVERLAP_WIDTH-1)/2) > RAM_DEPTH) begin
                depth_err = 1'b1;
            end else begin
                depth_err = 1'b0;
            end
        end else begin
            //row save = 1
            if((col_end - col_start) > RAM_DEPTH - 1) begin
                depth_err = 1'b1;
            end else begin
                depth_err = 1'b0;
            end
        end
    end else begin
        //row save = 1
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

assign row_less   = row_max[TIMING_CNT_WIDTH-1:0] < col_end - col_start ? 1'b1 : 1'b0;
assign col_less   = hblank_low < col_end - col_start ? 1'b1 : 1'b0;
assign row_err    = row_start > row_end ? 1'b1 : 1'b0;
assign col_err    = col_start > col_end ? 1'b1 : 1'b0;
assign row_over   = row_cnt[TIMING_CNT_WIDTH-1:0] == {TIMING_CNT_WIDTH{1'b1}} ? 1'b1 : 1'b0;
assign col_over   = col_cnt[TIMING_CNT_WIDTH-1:0] == {TIMING_CNT_WIDTH{1'b1}} ? 1'b1 : 1'b0;
assign width_err  = col_over | row_over;



`endif


endmodule // data_com
