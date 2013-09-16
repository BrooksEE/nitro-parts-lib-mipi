module mipi_csi2_des 
  #(DATA_WIDTH=8)
  (
   input 	     resetb,
   input         enable,
   
   input 	     mcp,
   input 	     mcn,
   input 	     mdp,
   input 	     mdn,
   input         mdp_lp,
   input         mdn_lp,

   output        img_clk,
   output reg [DATA_WIDTH-1:0] dato,
   output reg 	     lvo,
   output reg 	     fvo,
   input         md_polarity
   );

   //wire clk_in_int, clk_div, clk_in_int_buf, clk_in_int_inv, serdes_strobe;
   //

   wire phy_we,phy_clk;
   wire [7:0] phy_data;

   mipi_phy_des mipi_phy_des(
      .resetb       (resetb),
      .mcp          (mcp),
      .mcn          (mcn),
      .mdp          (mdp),
      .mdn          (mdn),
      .mdp_lp       (mdp_lp),
      .mdn_lp       (mdn_lp),
      .clk          (phy_clk),
      .we           (phy_we),
      .data         (phy_data),
      .md_polarity  (md_polarity)
   );

   // TODO generate img_clk instead
   // so we can have it run slower
   // and clock out 10 bit data.
   // where to put the BUFG for img_clk
   assign img_clk = phy_clk;

   parameter ST_IDLE=0, ST_HEADER=1, ST_DATA=2, ST_EOT=3; 
   parameter ID_FRAME_START=0, ID_FRAME_END=1, ID_LINE_START=2, ID_LINE_END=3;
   reg [1:0] state;

   reg [1:0] header_cnt; // read the header
   reg [7:0] header[0:3];
   reg [15:0] wc;
   reg dat_pos;
   always @(posedge phy_clk) begin
      if (!resetb) begin
          lvo <= 0;
          fvo <= 0;
          dato <= 0;
          header_cnt <= 0;
          //img_clk <= 0;
          dat_pos <= 0;
      end else begin

          //img_clk <= !img_clk;

          if (state == ST_IDLE) begin
             if (phy_we) begin
                header_cnt <= 1;
                state <= ST_HEADER;
                header[0] <= phy_data;
             end
          end else if (state == ST_HEADER) begin
             if (header_cnt <= 3) begin
                header[header_cnt] <= phy_data;
                header_cnt <= header_cnt+1;
             end

             if (header_cnt == 3) begin
                // collect the header
                if (header[0][5:0] == ID_FRAME_START) begin
                   fvo <= 1;
                   state <= ST_EOT;
                end else if (header[0][5:0] == ID_FRAME_END) begin
                   fvo <= 0; 
                   state <= ST_EOT;
                end else if (header[0][5:0] == 6'h2a) begin
                   wc <= { header[2], header[1] };
                   state <= ST_DATA;
                   //dat_pos <= 1;
                end else begin
                   state <= ST_EOT; // ignore all other headers right now
                end

             end
          end else if (state == ST_DATA) begin
             //dat_pos <= !dat_pos;

             if (wc > 0 && phy_we) begin
                lvo <= 1;
                if (DATA_WIDTH==10) begin 
                 // TODO
                end else if (DATA_WIDTH==8)
                begin
                   dato[7:0] <= phy_data;
                   wc <= wc - 1;
                end
                //if (dat_pos == 0) begin
                //   dato[9:8] <= phy_data[DATA_WIDTH-9:0];
                //end else begin
                //   dato[7:0] <= phy_data;
                //   wc <= wc - 1;
                //end
             end else begin
                state <= ST_EOT;
                lvo <= 0;
                // TODO a frame will also have two bytes for the checksum
             end
          end else if (state == ST_EOT) begin
             // ignore bytes while phy_we high
             if (!phy_we) begin
                state <= ST_IDLE;
             end
          end
      end
   end
   
   
endmodule
