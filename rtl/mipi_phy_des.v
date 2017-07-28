
module mipi_phy_des (
     input 	  resetb,
     input 	  mcp,
     input 	  mcn,
     input 	  mdp,
     input 	  mdn,
     input 	  mdp_lp,
     input 	  mdn_lp,
     output 	  clk,
     output reg   we,
     output [7:0] data,
     input 	  md_polarity,
`ifdef ARTIX
     input 	  mmcm_reset, 
     output 	  locked,
     input 	  psclk,
     input 	  psen,
     input 	  psincdec,
     output 	  psdone, 
`endif
`ifdef MIPI_RAW_OUTPUT
     output [7:0] q_out,
     output [1:0] state,
     output [2:0] sync_pos,
`endif
     input [7:0]  mipi_tx_period
);

   reg resetb_s;
   always @(posedge clk or negedge resetb) begin
     if (!resetb) begin
        resetb_s <= 0;
     end else begin
        resetb_s <= 1;
     end
   end
   wire reset = !resetb_s;

   parameter ST_START=0, ST_SYNC=1, ST_SHIFT=2;
   wire [7:0] q;

`ifdef ARTIX
`ifndef verilator // TODO Artix unisims

   IBUFGDS ibufgclk(.I(mcp), .IB(mcn), .O(clk_in_int));

//`ifdef MIPI_MMCM_PHASE
//   localparam MIPI_MMCM_PHASE= `MIPI_MMCM_PHASE ;
//`else
//   localparam MIPI_MMCM_PHASE=90;
//`endif			      
   localparam MIPI_MMCM_PHASE=0;

   MMCME2_ADV
     #(
       .CLKIN1_PERIOD(2.5),
       .CLKFBOUT_USE_FINE_PS("TRUE"),
       .BANDWIDTH("OPTIMIZED"), // Jitter programming (OPTIMIZED, HIGH, LOW)
       .CLKFBOUT_PHASE(MIPI_MMCM_PHASE),//Phase offset in deg of CLKFB (-360.000-360.000).
       .CLKFBOUT_MULT_F(4),
       .DIVCLK_DIVIDE(1),
       .CLKOUT0_DIVIDE_F(4),
       .CLKOUT1_DIVIDE(16),
       .CLKOUT2_DIVIDE(1),
       .CLKOUT3_DIVIDE(1),
       .CLKOUT4_DIVIDE(1),
       .CLKOUT5_DIVIDE(1),
       .CLKOUT6_DIVIDE(1),
       .CLKOUT0_DUTY_CYCLE(0.5),
       .CLKOUT1_DUTY_CYCLE(0.5),
       .CLKOUT2_DUTY_CYCLE(0.5),
       .CLKOUT3_DUTY_CYCLE(0.5),
       .CLKOUT4_DUTY_CYCLE(0.5),
       .CLKOUT5_DUTY_CYCLE(0.5),
       .CLKOUT6_DUTY_CYCLE(0.5),
       .CLKOUT0_PHASE(0.0),
       .CLKOUT1_PHASE(0.0),
       .CLKOUT2_PHASE(0.0),
       .CLKOUT3_PHASE(0.0),
       .CLKOUT4_PHASE(0.0),
       .CLKOUT5_PHASE(0.0),
       .CLKOUT6_PHASE(0.0),
       .CLKOUT4_CASCADE("FALSE"),
       .REF_JITTER1(0.0),
       .STARTUP_WAIT("FALSE")
       )
   u_mmcm_mipi_clk
   (
    .CLKIN1(clk_in_int),
    .CLKFBIN(clk_in2),
    .RST(mmcm_reset),
    .PWRDWN(1'b0),
    .CLKOUT0(clk_in2),
    .CLKOUT0B(),
    .CLKOUT1(clk),
    .CLKOUT1B(),
    .CLKOUT2 (),
    .CLKOUT2B(),
    .CLKOUT3 (),
    .CLKOUT3B(),
    .CLKOUT4 (),
    .CLKOUT5 (),
    .CLKOUT6 (),
    .CLKFBOUT(),
    .CLKFBOUTB(),
    .LOCKED(locked),
    .PSCLK(psclk),
    .PSEN(psen),
    .PSDONE(psdone),
    .PSINCDEC(psincdec),
    .CLKIN2(1'b0),
    .CLKINSEL(1'b1),
    .DADDR(7'b0),
    .DI(16'b0),
    .DWE(1'b0),
    .DCLK(1'b0),
    .DO(),
    .DRDY(),
    .CLKINSTOPPED(),
    .CLKFBSTOPPED()
    );

//   BUFR #(.BUFR_DIVIDE("1"))
//   bufr_inst2
//     (.I(clk_in),
//      .O(clk_in2),
//      .CE(1'b1),
//      .CLR(1'b0)
//      );
//
//   // Set up the clock for use in the serdes
//   BUFR #(.BUFR_DIVIDE("4"))
//   bufr_inst
//     (.O(clk),
//      .I(clk_in),
//      .CE(1'b1),
//      .CLR(1'b0)
//      );
   wire dat;
   IBUFDS ibufdat0(.I(mdp), .IB(mdn), .O(dat));


   ISERDESE2
     #(.DATA_RATE("DDR"),
       .DATA_WIDTH(8),
       .INTERFACE_TYPE("NETWORKING"),
       .NUM_CE(1),
       .SERDES_MODE("MASTER"),
       .IOBDELAY("NONE")
       )
     serdes
       (.CLK(clk_in2),
	.CLKB(~clk_in2),
	.CE1(1'b1),
	.CE2(1'b1),
	.RST(~resetb_s),
	.CLKDIV(clk),
	.CLKDIVP(1'b0),
	.OCLK(1'b0),
	.OCLKB(1'b0),
	.BITSLIP(1'b0),
	.SHIFTIN1(1'b0),
	.SHIFTIN2(1'b0),
	.OFB(1'b0),
	.DYNCLKDIVSEL(1'b0),
	.DYNCLKSEL(1'b0),
	.Q1(q[7]),
	.Q2(q[6]),
	.Q3(q[5]),
	.Q4(q[4]),
	.Q5(q[3]),
	.Q6(q[2]),
	.Q7(q[1]),
	.Q8(q[0]),
	.D(dat),
	.DDLY(1'b0),
	.O(),
	.SHIFTOUT1(),
	.SHIFTOUT2()

	);

`endif // verilator

`else
   wire clk_div, clk_in_int_buf, clk_in_int_inv, serdes_strobe;
   IBUFGDS #(.IOSTANDARD("LVDS_33"))
   ibufgclk(.I(mcp), .IB(mcn), .O(clk_in_int));

   // Set up the clock for use in the serdes
   BUFIO2 #(
	    .DIVIDE_BYPASS ("FALSE"),
	    .I_INVERT      ("FALSE"),
	    .USE_DOUBLER   ("TRUE"),
	    .DIVIDE        (8))
   bufio2_inst
     (.DIVCLK       (clk_div),
      .IOCLK        (clk_in_int_buf),
      .SERDESSTROBE (serdes_strobe),
      .I            (clk_in_int)
      );

   // also generated the inverted clock
   BUFIO2
     #(.DIVIDE_BYPASS ("FALSE"),
       .I_INVERT      ("TRUE"),
       .USE_DOUBLER   ("FALSE"),
       .DIVIDE        (8))
   bufio2_inv_inst
     (.DIVCLK        (),
      .IOCLK        (clk_in_int_inv),
      .SERDESSTROBE (),
      .I            (clk_in_int));
   // Buffer up the divided clock
   BUFG clkdiv_buf_inst
     (.O (clk),
      .I (clk_div));

     serdes serdes0
       (.clk_serdes0(clk_in_int_buf),
        .clk_serdes1(clk_in_int_inv),
        .serdes_strobe(serdes_strobe),
        .clk_div(clk),
        .reset(!resetb),
        .datp(mdp),
        .datn(mdn),
        .q(q));
`endif

     // find word alignment by finding row sync pattern
     reg [7:0]  q0, q1;
     reg [7:0]  q_shift[0:7];
     wire [15:0] shift_data = { q0, q1 } ^ {16{md_polarity}};
     integer i;
     always @(shift_data) begin
			q_shift[0] = shift_data[15:8];
			for (i=1; i<8; i=i+1) begin
				q_shift[i] = q_shifter(shift_data, i);
			end
     end

     always @(posedge clk or negedge resetb_s) begin
        if (!resetb_s) begin
           q0 <= 0;
           q1 <= 0;
        end else begin
           q0 <= q;
           q1 <= q0;
        end
     end

     reg [1:0] state;
     reg [2:0] sync_pos;
     reg [7:0] data_i;

     assign data = data_i;
`ifdef MIPI_RAW_OUTPUT
     assign q_out = q_shift[0];
`endif

   reg 	       mdp_lp_s, mdn_lp_s;
	// synthesis attribute IOB of mdp_lp_s is "TRUE";
	// synthesis attribute IOB of mdn_lp_s is "TRUE";
   reg [7:0] 	     stall_count;



     always @(posedge clk or negedge resetb_s) begin
        if (!resetb_s) begin
            data_i <= 0;
            we <= 0;
            state <= ST_START;
            sync_pos <= 0;
            mdp_lp_s <= 1;
            mdn_lp_s <= 1;
            stall_count <= 0;

        end else begin
    	    mdp_lp_s <= mdp_lp;
	        mdn_lp_s <= mdn_lp;

            if (state == ST_START) begin
                we <= 0;

                if (!mdp_lp_s || !mdn_lp_s) begin
		           if(stall_count >= mipi_tx_period) begin
                     if (!mdp_lp_s && !mdn_lp_s) begin
                        state <= ST_SYNC;
                        stall_count <= 0;
                     end
    	    	   end else begin
            	     stall_count <= stall_count + 1;
                   end
                end else begin
		           stall_count <= 0;
        		end
            end else if (state == ST_SYNC) begin
                if (mdp_lp_s || mdn_lp_s) begin
                    state <= ST_START;
                end else begin
                    for (i=0;i<8;i=i+1) begin
                        if (q_shift[i] == 8'hb8) begin
                            /* verilator lint_off WIDTH */
                            sync_pos <= i;
                            /* verilator lint_on WIDTH */
                            state <= ST_SHIFT;
                        end
                    end
                end
            end else if (state == ST_SHIFT) begin
                if (mdp_lp_s || mdn_lp_s) begin
                    state <= ST_START;
                    we <= 0;
                end else begin
                    we <= 1;
                    data_i <= q_shift[sync_pos];
                end

            end

        end
     end


   function [7:0] q_shifter;
      input [15:0] qi;
      input integer s;
      reg [15:0] word;
      begin
        word = qi << s;
        q_shifter = word[15:8];
      end
   endfunction

endmodule

`ifndef ARTIX
module serdes
  (
   input 	clk_serdes0,
   input 	clk_serdes1,
   input 	serdes_strobe,
   input 	clk_div,
   input 	reset,
   input 	datp,
   input 	datn,
   output [7:0] q
   );

   wire 	dat_s, dat;
   wire [7:0] 	q_int;
   IBUFDS  #(.DIFF_TERM("TRUE"),
	     .IOSTANDARD("LVDS_33"))
   ibufdat0(.I(datp), .IB(datn), .O(dat));

   ISERDES2 #(
	      .BITSLIP_ENABLE("FALSE"),
	      .DATA_RATE("DDR"),
	      .DATA_WIDTH(8),
	      .INTERFACE_TYPE("NETWORKING"),
	      .SERDES_MODE("MASTER")
	      )
   serdes0a
     (.CLK0(clk_serdes0),
      .CLK1(clk_serdes1),
      .CLKDIV(clk_div), // parallel data clock
      .CE0(1'b1), // clock enable for all registers
      .BITSLIP(1'b0), // invoke bitslip when high. sycn to CLKDIV
      .D(dat),
      .RST(reset),
      .IOCE(serdes_strobe), //data strobe signal
      .SHIFTIN(1'b0), // cascade-in signal

      .CFB0(),
      .CFB1(),
      .DFB(),
      .SHIFTOUT(dat_s),
      .FABRICOUT(),
      .Q1(q_int[4]),
      .Q2(q_int[5]),
      .Q3(q_int[6]),
      .Q4(q_int[7]),
      .VALID(),
      .INCDEC()
      );

   ISERDES2 #(
	      .DATA_RATE("DDR"),
	      .DATA_WIDTH(8),
	      .BITSLIP_ENABLE("FALSE"),
	      .SERDES_MODE("SLAVE"),
	      .INTERFACE_TYPE("NETWORKING")
	      )
   serdes0b
     (.CLK0(clk_serdes0),
      .CLK1(clk_serdes1),
      .CLKDIV(clk_div), // parallel data clock
      .CE0(1'b1), // clock enable for all registers
      .BITSLIP(1'b0), // invoke bitslip when high. sycn to CLKDIV
      .D(1'b0),
      .RST(reset),
      .IOCE(serdes_strobe), //data strobe signal
      .SHIFTIN(dat_s), // cascade-in signal

      .CFB0(),
      .CFB1(),
      .DFB(),
      .SHIFTOUT(),
      .FABRICOUT(),
      .Q1(q_int[0]),
      .Q2(q_int[1]),
      .Q3(q_int[2]),
      .Q4(q_int[3]),
      .VALID(),
      .INCDEC()
      );

   assign q = q_int;

endmodule
`endif
