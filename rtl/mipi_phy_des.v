
module mipi_phy_des (
     input            resetb,
     input            mcp,   
     input            mcn,   
     input            mdp,   
     input            mdn,   
     input            mdp_lp,
     input            mdn_lp,
     output           clk,
     output reg       we,
     output [7:0] data,
     input            md_polarity,
     input  [7:0]   mipi_tx_period
`ifdef MIPI_RAW_OUTPUT
     ,
     output [7:0]     q_out
`endif
);

   reg resetb_s;
   always @(posedge clk or negedge resetb) begin
     if (!resetb) begin
        resetb_s <= 0;
     end else begin
        resetb_s <= 1;
     end
   end

   wire clk_in_int, clk_div, clk_in_int_buf, clk_in_int_inv, serdes_strobe;

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


     parameter ST_START=0, ST_SYNC=1, ST_SHIFT=2;

     wire [7:0] q;
     serdes serdes0
       (.clk_serdes0(clk_in_int_buf),
        .clk_serdes1(clk_in_int_inv),
        .serdes_strobe(serdes_strobe),
        .clk_div(clk),
        .reset(!resetb),
        .datp(mdp),
        .datn(mdn),
        .q(q));

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
