module mipi_csi2_des 
  (
   input 	     resetb,
   
   input 	     mcp,
   input 	     mcn,
   input 	     mdp,
   input 	     mdn,
   input         mdp_lp,
   input         mdn_lp,

   output 	     img_clk,
   output [9:0]      dato,
   output reg 	     lvo,
   output reg 	     fvo
   );

   wire reset = !resetb;
   wire clk_in_int, clk_div, clk_in_int_buf, clk_in_int_inv, serdes_strobe;
   
   IBUFGDS #(.IOSTANDARD("LVDS_33")) 
   ibufgclk(.I(mcp), .IB(mcn), .O(clk_in_int));

   // Set up the clock for use in the serdes
   BUFIO2 #(
	    .DIVIDE_BYPASS ("FALSE"),
	    .I_INVERT      ("FALSE"),
	    .USE_DOUBLER   ("TRUE"),
	    .DIVIDE        (6))
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
       .DIVIDE        (6))
   bufio2_inv_inst
     (.DIVCLK        (),
      .IOCLK        (clk_in_int_inv),
      .SERDESSTROBE (),
      .I            (clk_in_int));
   // Buffer up the divided clock
   BUFG clkdiv_buf_inst
     (.O (img_clk),
      .I (clk_div));

   reg [2:0] shift_pos;
   
   // deserialize both channels
   wire [11:0] q;
   serdes serdes0
     (.clk_serdes0(clk_in_int_buf),
      .clk_serdes1(clk_in_int_inv),
      .serdes_strobe(serdes_strobe),
      .clk_div(img_clk),
      .reset(reset),
      .datp(mdp),
      .datn(mdn),
      .q(q[11:6]));
//   serdes serdes1
//     (.clk_serdes0(clk_in_int_buf),
//      .clk_serdes1(clk_in_int_inv),
//      .serdes_strobe(serdes_strobe),
//      .clk_div(img_clk),
//      .reset(reset),
//      .datp(dat1p),
//      .datn(dat1n),
//      .q(q[5:0]));
   assign q[5:0] = 0;
   

   // find word alignment by finding row sync pattern
   reg [11:0]  q0, q1;
   reg [11:0]  q_shift[0:5];
   always @(q0, q1) begin
      q_shift[0] = q0;
      q_shift[1] = q_shifter(q0, q1, 1);
      q_shift[2] = q_shifter(q0, q1, 2);
      q_shift[3] = q_shifter(q0, q1, 3);
      q_shift[4] = q_shifter(q0, q1, 4);
      q_shift[5] = q_shifter(q0, q1, 5);
   end
      
   reg [3:0] sync_count[0:5];
   integer   i;
   reg [5:0] sync_pos;
   reg [11:0] dato_bs, dato_bss, dato_bsss;
   reg 	      row_start;
   always @(posedge img_clk or negedge resetb) begin
      if(!resetb) begin
	 q0 <= 0;
	 q1 <= 0;
	 for(i=0; i<6; i=i+1) begin
	    sync_count[i] <= 0;
	 end
	 sync_pos <= 0;
	 shift_pos <= 0;
	 dato_bs <= 0;
	 row_start <= 0;
      end else begin
	 q0 <= q;
	 q1 <= q0;

	 for(i=0; i<6; i=i+1) begin
	    if((sync_count[i][1] == 0) && (q_shift[i] == 12'h000)) begin
	       sync_count[i] <= sync_count[i] + 1;
	       sync_pos[i] <= 0;
	    end else if((sync_count[i][1] == 1) && (q_shift[i] == 12'hFFF)) begin
	       sync_count[i] <= sync_count[i] + 1;
	       if(sync_count[i] == 7) begin
		  sync_pos[i] <= 1;
	       end else begin
		  sync_pos[i] <= 0;
	       end
	    end else begin
	       sync_count[i] <= 0;
	       sync_pos[i] <= 0;
	    end
	 end

	 shift_pos <= sync_pos[0] ? 0 :
		      sync_pos[1] ? 1 :
		      sync_pos[2] ? 2 :
		      sync_pos[3] ? 3 :
		      sync_pos[4] ? 4 :
		      sync_pos[5] ? 5 : shift_pos;

	 row_start <= |sync_pos;
	 dato_bs <= q_shift[shift_pos];
	 dato_bss<= { dato_bs[6], dato_bs[7], dato_bs[8], dato_bs[9], dato_bs[10], dato_bs[11], dato_bs[0], dato_bs[1], dato_bs[2], dato_bs[3], dato_bs[4], dato_bs[5] };
	 dato_bsss<= dato_bss;
      end
   end
   assign dato = dato_bsss[9:0];

   // find frame start from row start pulses
   reg [11:0] col_count, num_cols0, num_cols1;
   wire [11:0] next_col_count = col_count + 1;
   reg 	       lve;
   always @(posedge img_clk or negedge resetb) begin
      if(!resetb) begin
	 col_count  <= 0;
	 num_cols0  <= 0;
	 num_cols1  <= 0;
	 fvo        <= 0;
	 lve        <= 0;
	 lvo        <= 0;
      end else begin
	 lvo <= lve;
	 if(row_start) begin
	    fvo <= 1;
	    lve <= 1;
	    col_count <= 0;
	    num_cols0 <= next_col_count;
	    num_cols1 <= num_cols0;
	 end else begin
	    if(dato_bs == 12'h020) begin
	       lve <= 0;
	    end
	    if(num_cols0 != num_cols1 || next_col_count < num_cols0) begin
	       col_count <= next_col_count;
	    end else begin
	       fvo <= 0;
	       num_cols1 <= 0;
	    end
	 end
      end
   end
   
   function [11:0] q_shifter;
      input [11:0] qi0;
      input [11:0] qi1;
      input integer s;
      reg [11:0]    q_msbs;
      reg [11:0]    q_lsbs;
      begin
	 q_msbs = { qi1[11:6], qi0[11:6] } >> s;
	 q_lsbs = { qi1[5:0],  qi0[5:0]  } >> s;
	 q_shifter = { q_msbs[5:0], q_lsbs[5:0] };
      end
   endfunction
   
endmodule // deserialize


module serdes
  (
   input 	clk_serdes0,
   input 	clk_serdes1,
   input 	serdes_strobe,
   input 	clk_div,
   input 	reset,
   input 	datp,
   input 	datn,
   output [5:0] q
   );

   wire 	dat_s, dat;
   wire [7:0] 	q_int;
   
   IBUFDS  #(.DIFF_TERM("TRUE"),
	     .IOSTANDARD("LVDS_33"))
   ibufdat0(.I(datp), .IB(datn), .O(dat));
   
   ISERDES2 #(
	      .BITSLIP_ENABLE("FALSE"),
	      .DATA_RATE("DDR"),
	      .DATA_WIDTH(6),
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
      .Q1(q_int[3]),
      .Q2(q_int[2]),
      .Q3(q_int[1]),
      .Q4(q_int[0]),
      .VALID(),
      .INCDEC()
      );

   ISERDES2 #(
	      .DATA_RATE("DDR"),
	      .DATA_WIDTH(6),
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
      .Q1(q_int[7]),
      .Q2(q_int[6]),
      .Q3(q_int[5]),
      .Q4(q_int[4]),
      .VALID(),
      .INCDEC()
      );

   assign q = q_int[5:0];
   
endmodule // serdes

//module unpack
//  (input clk,
//   input [11:0] d,
//   output reg [11:0] q
//   );
//
//   reg [11:0] 	 d_s, d_ss;
//   
//   always @(posedge clk) begin
//      d_s <= d;
//      d_ss <= d_s;
//   end
//endmodule
	      
