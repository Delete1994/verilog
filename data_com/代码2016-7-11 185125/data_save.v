module data_save (
    clk,
    ch_clk,
    ce,
    sclr,
    video_data_in,
    //from receive,for write
    wr_addr1,
    wr_addr2,
    pp_flagw,
    pp_flagr,
    effect_reigon,
    //from send, for read
    addra_s,
    ena_s,
    douta_s,

    addrb_s,
    enb_s,
    doutb_s
    );


parameter VIDEO_DATA_WIDTH  = 18;                   //视频数据信号宽度
parameter TIMES             = 1;                    //输入块除以输出块
parameter RAM_DEPTH         = 100;                  //行缓存ram深度
localparam ADDR_WIDTH       = clogb2(RAM_DEPTH-1);  //addra,addrb width

input                               sclr;
input                               ce;
input                               clk;
input                               ch_clk;
input [VIDEO_DATA_WIDTH-1'b1:0]     video_data_in;
input                               pp_flagw;       //乒乓操作标志位
input                               pp_flagr;       //乒乓操作标志位
input                               effect_reigon;  //接收数据的有效区域
input [ADDR_WIDTH-1'b1:0]           wr_addr1;        //接收指针，ram0使用
input [ADDR_WIDTH-1'b1:0]           wr_addr2;       //发送指针，ram1使用
input [ADDR_WIDTH-1:0]              addra_s;        //send --> receive
input [ADDR_WIDTH-1:0]              addrb_s;        //send --> receive
input                               ena_s;          //send --> receive
input                               enb_s;          //send --> receive

output [VIDEO_DATA_WIDTH-1'b1:0]    douta_s;        //send <-- receive
output [VIDEO_DATA_WIDTH-1'b1:0]    doutb_s;        //send <-- receive

reg    [1:0]                        wea;            //RAM1,RAM0写使能，1：a端口只写，0：a端只读
reg    [1:0]                        ena_w;          //RAM a port使能
reg    [2*VIDEO_DATA_WIDTH-1'b1:0]  dina;           //a port 写的数据

reg    [2*ADDR_WIDTH-1:0]           addra_r;        //RAM a port address
reg    [2*ADDR_WIDTH-1:0]           addrb;          //RAM a port address
reg    [1:0]                        ena_r;          //RAM a port使能
reg    [1:0]                        enb;            //RAM a port使能
reg    [VIDEO_DATA_WIDTH-1'b1:0]    douta_s;        //port a
reg    [VIDEO_DATA_WIDTH-1'b1:0]    doutb_s;
reg    [clogb2(TIMES-1)-1:0]        cnt_en_slow;
reg    [VIDEO_DATA_WIDTH-1:0]       video_data_in_d1;

wire   [2*ADDR_WIDTH-1:0]           addra;          //RAM a port address
wire   [1:0]                        ena;            //RAM a port使能
wire   [2*VIDEO_DATA_WIDTH-1'b1:0]  douta;
wire   [2*VIDEO_DATA_WIDTH-1'b1:0]  doutb;
wire                                en_slow;


//例化两个RAM
generate
    genvar i;
    for (i = 0; i < 2'd2; i=i+1'b1) begin : blk_ram_f
        true_dual_ram #(
        .RAM_WIDTH(VIDEO_DATA_WIDTH),         // Specify RAM data width
        .RAM_DEPTH(RAM_DEPTH),                // Specify RAM depth (number of entries)
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
        .INIT_FILE("")                        // Specify name/location of RAM initialization file if using one (leave blank if not)
        ) blk_ram (
        .clka(clk),     // Clock
        .wea(wea[i]),       // Port A write enable
        .web(1'd0),       // Port B write enable,only read ,so not used
        .ena(ena[i]),       // Port A RAM Enable, for additional power savings, disable port when not in use
        .enb(enb[i]),       // Port B RAM Enable, for additional power savings, disable port when not in use
        .addra(addra[i*ADDR_WIDTH + ADDR_WIDTH-1 -:ADDR_WIDTH]),// Port A address bus
        .addrb(addrb[i*ADDR_WIDTH + ADDR_WIDTH-1 -:ADDR_WIDTH]),   // Port B address bus, width determined from RAM_DEPTH
        .dina(dina[i*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH]),   // Port A RAM input data, width determined from RAM_WIDTH,共用
        .dinb({VIDEO_DATA_WIDTH{1'b0}}),  // Port B RAM input data, width determined from RAM_WIDTH
        .douta(douta[i*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH]),   // Port A RAM output data, width determined from RAM_WIDTH
        .doutb(doutb[i*VIDEO_DATA_WIDTH+VIDEO_DATA_WIDTH-1'b1 -:VIDEO_DATA_WIDTH]),  // Port B RAM output data, width determined from RAM_WIDTH
        .rsta(1'd0),     // Port A output reset (does not affect memory contents)
        .rstb(1'd0),     // Port B output reset (does not affect memory contents)
        .regcea(1'd1),   // Port A output register enable
        .regceb(1'd1)    // Port B output register enable
        );
    end
endgenerate

//en signal
always@(posedge clk)
    if(sclr)
        cnt_en_slow <= 0;
    else if(cnt_en_slow == TIMES - 1)
        cnt_en_slow <= 0;
    else
        cnt_en_slow <= cnt_en_slow + 1;

assign en_slow = (cnt_en_slow == TIMES - 1);

always @(posedge ch_clk) begin
    if(sclr) begin
        video_data_in_d1 <= 0;
    end else if(ce) begin
        video_data_in_d1 <= video_data_in;
    end
end

//数据缓存
//还需要低功耗处理
always @(*) begin
    if(ce) begin
        //有效区间
        if(effect_reigon && en_slow) begin
            if(pp_flagw) begin//write ram0 for line 0,2,4
                ena_w    = 2'b01;
            end else begin //write ram1 for line  1,3,5
                ena_w    = 2'b10;
            end
        //不在有效区间,但是可能在读，所以还是要使能ena,enb
        end else begin
            ena_w  = 2'b00;
        end
    end else begin
        ena_w  = 2'b00;
    end
end


//数据缓存
//还需要低功耗处理
always @(*) begin
    if(ce) begin
        //有效区间
        if(effect_reigon) begin//在effect,pp_flagw上升沿的同时，wea，web有毛刺！
            if(pp_flagw) begin//write ram0 for line 0,2,4
                wea      = 2'b01;
                dina  = {{VIDEO_DATA_WIDTH{1'b0}},video_data_in_d1};
            end else begin //write ram1 for line  1,3,5
                wea      = 2'b10;
                dina  = {video_data_in_d1,{VIDEO_DATA_WIDTH{1'b0}}};
            end
        //不在有效区间,但是可能在读，所以还是要使能ena,enb
        end else begin
            wea    = 2'b00;//只读
            dina   = 0;
        end
    end else begin
        wea    = 2'b00;//只读
        dina   = 0;
    end
end


//读RAM乒乓操作
//读地址提前hbo_neg两个clk赋值,
//在整个hbo低电平控制输出数据
//有些情况ena_r端口没有使用，从而为不定态，蓝色，未被驱动，不影响结果
always @(*) begin
    if(pp_flagr) begin//1 for ram1 when read
        enb      = {enb_s,1'b0};
        ena_r    = {ena_s,1'b0};
        addrb    = {addrb_s,{ADDR_WIDTH{1'b0}}};
        addra_r  = {addra_s,{ADDR_WIDTH{1'b0}}};

        doutb_s  = doutb[VIDEO_DATA_WIDTH*2-1 :VIDEO_DATA_WIDTH];
        douta_s  = douta[VIDEO_DATA_WIDTH*2-1 :VIDEO_DATA_WIDTH];
    end else begin
        enb      = {1'b0,enb_s};
        ena_r    = {1'b0,ena_s};
        addrb    = {{ADDR_WIDTH{1'b0}},addrb_s};
        addra_r  = {{ADDR_WIDTH{1'b0}},addra_s};

        doutb_s  = doutb[VIDEO_DATA_WIDTH-1 :0];
        douta_s  = douta[VIDEO_DATA_WIDTH-1 :0];
    end
end

//RAM地址合成
assign ena = ena_r | ena_w;
//ram0 地址选择，是读还是写
assign addra[ADDR_WIDTH-1:0] = wea[0] ? wr_addr1 : addra_r[ADDR_WIDTH-1:0];
//ram1 地址选择，是读还是写
assign addra[ADDR_WIDTH*2-1:ADDR_WIDTH] = wea[1] ? wr_addr2 : addra_r[ADDR_WIDTH*2-1:ADDR_WIDTH];

//  The following function calculates the address width based on specified RAM depth
function integer clogb2;
    input integer depth;
    for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
endfunction

endmodule