////////////////////////////////////////////////////////////////////////////////
// Module: Red Pitaya arbitrary signal generator testbench.
// Authors: Matej Oblak, Iztok Jeras
// (c) Red Pitaya  http://www.redpitaya.com
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module gen_top_tb #(
  // time period
  realtime  TP = 8.0ns,  // 125MHz
  // types
  type U16 = logic [16-1:0],
  type S16 = logic signed [16-1:0],
  type S14 = logic signed [14-1:0],
  // data parameters
  type DT = S14,
  type DTM = S16,
  type DTS = S14,
  // buffer parameters
  int unsigned CWM = 14,  // counter width magnitude (fixed point integer)
  int unsigned CWF = 16   // counter width fraction  (fixed point fraction)
);

////////////////////////////////////////////////////////////////////////////////
// DAC signal generation
////////////////////////////////////////////////////////////////////////////////

// syste signals
logic                  clk ;
logic                  rstn;

// interrupts
logic           irq_trg;  // trigger
logic           irq_stp;  // stop

// stream
axi4_stream_if #(.DN (1), .DT (DT)) str (.ACLK (clk), .ARESETn (rstn));

// events
typedef struct packed {
  logic str;  // software start
  logic stp;  // software stop
  logic trg;  // software trigger
  logic per;  // period
  logic lst;  // last
} evn_asg_t;

evn_asg_t evn;

// event parameters
localparam int unsigned EW = $bits(evn_asg_t);  // event array width

////////////////////////////////////////////////////////////////////////////////
// clock
////////////////////////////////////////////////////////////////////////////////

// DAC clock
initial        clk = 1'b0;
always #(TP/2) clk = ~clk;

// clocking 
default clocking cb @ (posedge clk);
  input  rstn;
endclocking: cb

// DAC reset
initial begin
  rstn <= 1'b0;
  ##4;
  rstn <= 1'b1;
end

// ADC cycle counter
int unsigned dac_cyc=0;
always_ff @ (posedge clk)
dac_cyc <= dac_cyc+1;

////////////////////////////////////////////////////////////////////////////////
// test sequence
////////////////////////////////////////////////////////////////////////////////

logic        [ 32-1: 0] rdata;
logic signed [ 32-1: 0] rdata_blk [];

////////////////////////////////////////////////////////////////////////////////
// signal generation
////////////////////////////////////////////////////////////////////////////////

//int buf_len = 2**CWM;
int buf_len = 8;
real freq  = 10_000; // 10kHz
real phase = 0; // DEG

initial begin
  ##10;
  // write table
  for (int i=0; i<buf_len; i++) begin
    busm_tbl.write((i*2), i);  // write table
  end
  // read table
  rdata_blk = new [80];
  for (int i=0; i<buf_len; i++) begin
    busm_tbl.read((i*2), rdata_blk [i]);  // read table
  end
  // configure amplitude and DC offset
  busm.write('h48, 1 << ($bits(DTM)-2));  // amplitude
  busm.write('h4c, 0);                    // DC offset
  // configure frequency and phase
  busm.write('h20,  buf_len                    * 2**CWF - 1);  // table size
  busm.write('h24, (buf_len * (phase/360.0)  ) * 2**CWF    );  // offset
//busm.write('h28, (buf_len * (freq*TP/10**6)) * 2**CWF - 1);  // step
  busm.write('h28, 1                           * 2**CWF - 1);  // step
  // configure burst mode
  busm.write('h30, 2'b00);  // burst disable
  // all events are SW driven
  busm.write('h10, 5'b00001);  // start
  busm.write('h14, 5'b00010);  // stop
  busm.write('h18, 5'b00100);  // trigger
  // start
  busm.write('h00, 4'b0010);
  ##22;

  // reset
  busm.write('h00, 4'b0001);
  ##20;

  // configure frequency and phase
  busm.write('h24, 0 * 2**CWF    );  // offset
  busm.write('h28, 1 * 2**CWF - 1);  // step
  // configure burst mode
  busm.write('h30, 2'b01);  // burst enable
  busm.write('h34, 4-1);  // burst data length
  busm.write('h38, 8-1);  // burst      length
  busm.write('h3c, 4-1);  // burst number of repetitions
  // start
  busm.write('h00, 4'b0010);
  ##120;

  // stop (reset)
  busm.write('h00, 4'b0001);
  ##20;

  // end simulation
  ##20;
  $stop();
  //$finish();
end

////////////////////////////////////////////////////////////////////////////////
// module instances
////////////////////////////////////////////////////////////////////////////////

sys_bus_if bus     (.clk (clk), .rstn (rstn));
sys_bus_if bus_tbl (.clk (clk), .rstn (rstn));

sys_bus_model busm     (.bus (bus    ));
sys_bus_model busm_tbl (.bus (bus_tbl));

gen_top #(
  .DT  (DT),
  .DTM (DTM),
  .DTS (DTS),
  .EW  (EW)
) gen_top (
  // stream output
  .sto      (str),
  // external events
  .evn_ext  (evn),
  // event sources
  .evn_str  (evn.str),
  .evn_stp  (evn.stp),
  .evn_trg  (evn.trg),
  .evn_per  (evn.per),
  .evn_lst  (evn.lst),
  // system bus
  .bus      (bus),
  .bus_tbl  (bus_tbl)
);

// stream drain
assign str.TREADY = 1'b1;

////////////////////////////////////////////////////////////////////////////////
// waveforms
////////////////////////////////////////////////////////////////////////////////

initial begin
  $dumpfile("gen_top_tb.vcd");
  $dumpvars(0, gen_top_tb);
end

endmodule: gen_top_tb