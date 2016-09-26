

module mipi_csi2_ser
   #(parameter DATA_WIDTH=8,
     parameter FIFO_ADDR_WIDTH=5 // determin max depth of FIFO queue
     ) // width of data bus
   (

       input resetb,
       input enable,

       input pixclk,
       input [4:0] lp_clk_div, // lp mipi mode can run max 10 mhz

       input [DATA_WIDTH-1:0] data,
       input [3:0] pixel_width,
       input [15:0] num_rows,
       input [15:0] num_cols,
       input vsync,
       input href,
       
       output mcp, // output clock
       output mcn, 
       output mdp, // output data 
       output mdn, 

       output mdp_lp, // low power data output
       output mdn_lp
   );

   // generate a high speed clock w/ pll
   // for reading image data and creating
   // converting to 8 bit data
    wire clk_hs;
   PLL_sim 
    #(.PLL_NAME("CSI2_hs"))
   pll_hs (
      .input_clk(pixclk),
      .output_clk(clk_hs),
      .pll_mult({28'b0,pixel_width}), //DATA_WIDTH, // TODO the clock can run slower i.e. 10/8 since we pack with no extra bits 
      .pll_div(8)
   ); 
   //wire clk_hs = pixclk;

   // generate low speed clock with clock divider.
   // divider should be set so that lp mode on
   // the phy layer runs approx 10 mhz
   reg [4:0] lp_clk_div_cnt;
   wire [4:0] lp_clk_div_next = lp_clk_div_cnt + 1;
   reg clk_ls;
   always @(posedge pixclk or negedge resetb) begin
      if (!resetb || !enable) begin
         lp_clk_div_cnt <= 5'b0;
         clk_ls <= 0;
      end else begin
         if (lp_clk_div_next == lp_clk_div) begin
            lp_clk_div_cnt <= 0;
            clk_ls <= 1;
         end else if (lp_clk_div_next == lp_clk_div >> 1) begin
            clk_ls <= 0;
            lp_clk_div_cnt <= lp_clk_div_cnt+1;
         end
      end
   end


   // FIFO image data is stored in.
   reg image_re, image_flush;
   wire image_empty, image_full;
   wire [DATA_WIDTH-1:0] datar;
   wire [FIFO_ADDR_WIDTH-1:0] image_free;
   wire [FIFO_ADDR_WIDTH-1:0] image_used;

   fifo_dualclk #(.ADDR_WIDTH(FIFO_ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) image_data (
       .wclk            (pixclk),
       .rclk            (clk_hs), 
       .we              (href && vsync),
       .re              (image_re),
       .resetb          (resetb),
       .flush           (image_flush),
       .full            (image_full),
       .empty           (image_empty),
       .wdata           (data),
       .rdata           (datar),
       .wFreeSpace      (image_free),
       .rUsedSpace      (image_used)
   );
   


   // packet states
   localparam ST_FRAME_START=0, ST_FRAME_END=1, ST_LINE_START=2, ST_LINE_END=3, ST_IDLE=4;
   // note 0-3 are the data types for the short packet data ids.

   reg [2:0] state;
   reg vsync_last;
   reg href_last;
   reg [15:0] image_wc;
   reg [15:0] image_wc_last;
   reg [15:0] frame_cnt;
   reg [15:0] line_cnt; // counting but not using it yet...
   always @(posedge pixclk or negedge resetb) begin
      if (!resetb) begin
        state <= ST_IDLE;
        vsync_last <= 0;
        href_last <= 0;
        image_wc <= 0;
        image_wc_last <= 0;
        frame_cnt <= 0;

      end else begin
        vsync_last <= vsync; 
        href_last <= href;
        if (!vsync_last && vsync) begin
            state <= ST_FRAME_START;
            frame_cnt <= frame_cnt + 1;
            line_cnt <= 0;
        end else if (vsync_last && !vsync) begin
            state <= ST_FRAME_END;
        end else if (!href_last && href && vsync) begin
            state <= ST_LINE_START;
            image_wc <= 1;
            line_cnt <= line_cnt + 1;
        end else if (href_last && !href && vsync) begin
            state <= ST_LINE_END;
            image_wc_last <= image_wc;
        end else begin
            state <= ST_IDLE;
        end

        if (href_last && href && vsync) begin
            image_wc <= image_wc + 1;
        end
      end
   end


   localparam ST_HS_SOT=1, ST_HS_DATA=2, ST_HS_EOT=3;
   reg [2:0] state_s;
   reg [2:0] state_saved;
   reg [2:0] substate; 
   reg [1:0] image_wc_cnt;
   reg [15:0] header_wc; 
   reg [15:0] ser_wc;
   wire phy_re;
   reg [7:0] data_ser;
   reg [7:0] data_ser_next;
   reg [7:0] data_id;
   reg hs_req, hs_req_s;
   reg ecc_cnt;
   wire [7:0] ecc = 8'hEC; // figure out
   reg [15:0] checksum;
   reg long_packet;
   reg image_empty_s;
   wire [15:0] frame_cnt_next = frame_cnt + 1;
   reg [7:0] lsbs;
   reg [2:0] packing; // count 0-4 and then the 4th byte send the lsbs

   wire [2:0] state_check = state_s != ST_IDLE ? state_s :
                            state_saved != ST_IDLE ? state_saved :
                            state_s;

   always @(posedge clk_hs or negedge resetb) begin
       if (!resetb) begin
          state_s <= ST_IDLE; 
          state_saved <= ST_IDLE;
          substate <= ST_IDLE;
          data_ser <= 0;
          data_ser_next <= 0;
          hs_req <= 0;
          hs_req_s <= 0;
          ecc_cnt <= 0;
          checksum <= 16'habcd;
          image_wc_cnt <= 0;
          header_wc <= 0;
          ser_wc <= 0;
          long_packet <= 0;
          data_id <= 0;
          image_empty_s <= 0;
          lsbs <= 0;
          packing <= 0;
          image_flush <= 0;
       end else begin
          state_s <= state; // TODO state can change before we finish tx the last state. 
                            // needs fixed... href<=0 vsync<=0 but vsync<=0
                            // not sent because state skipped.
          hs_req_s <= hs_req;
          image_empty_s <= image_empty;
          if (substate == ST_IDLE) begin
            hs_req <= 0;
            if (state_check != ST_IDLE && !phy_re) begin // if phy_re still high he hasn't finished last trans
                substate <= ST_HS_SOT;
                long_packet <= state_check == ST_LINE_START;
                if (state_check == ST_LINE_START) begin
                    data_id <= {2'b0, pixel_width == 8 ? 6'h2a : 6'h2b};
                end else begin
                    data_id <= {5'b0, state_check};
                end
                hs_req <= 1;
                if (state_check == ST_LINE_START) begin
                    if (pixel_width ==10) begin
                        if (image_wc_last == 0) begin
                            ser_wc <= num_cols * 5/4;
                            header_wc <= num_cols * 5/4;
                        end else begin
                            ser_wc <= image_wc_last * 5/4;
                            header_wc <= image_wc_last * 5 / 4;
                        end
                    end else if (pixel_width ==8) begin
                        if (image_wc_last == 0) begin
                            ser_wc <= num_cols;
                            header_wc <= num_cols;
                        end else begin
                            ser_wc <= image_wc_last; 
                            header_wc <= image_wc_last;
                        end
                    end
                end else if (state_check == ST_FRAME_START || state_check == ST_FRAME_END) begin
                    header_wc <= frame_cnt;
                end
                state_saved <= ST_IDLE;
            end else begin
                // size changes can cause fifo to not be emptied always
                image_flush <= !image_empty; // ignore data
                image_re <= 0;
            end
            
          end else if (substate == ST_HS_SOT) begin
            if (phy_re) begin
                data_ser <= data_id; // todo different data_id when in line data state.
                image_wc_cnt <= 0;
                ecc_cnt <= 0;
                substate <= ST_HS_DATA;
            end
          end else if (substate == ST_HS_DATA) begin
            // TODO probably better way to handle states
            // but hacking for now
            if (state_s != ST_IDLE) begin
                state_saved <= state_s;
                if (state_s == ST_FRAME_START) begin
                    // not keeping up with the last frame?
                    // just bail
                    substate <= ST_IDLE;
                end
            end
            if (image_wc_cnt < 2) begin
                image_wc_cnt <= image_wc_cnt + 1;
                data_ser <= header_wc[7:0];
                header_wc <= header_wc >> 8;
                ecc_cnt <= 0;
                packing <= 0;
                lsbs <= 0;
            end else begin
                if (!ecc_cnt) begin
                   ecc_cnt <= 1;
                   data_ser <= ecc; 
                   if (long_packet) begin
                      image_re <= 1;
                      ser_wc <= ser_wc - 1;
                   end else begin
                      substate <= ST_IDLE; // no eot on short packets
                   end
                end else begin

                   if (pixel_width == 8) begin
                    if (image_re) begin
                       data_ser <= datar[7:0];
                       ser_wc <= ser_wc - 1;
                       if (ser_wc == 0) begin
                         image_re <= 0; 
                       end
                    end else begin
                       substate <= ST_HS_EOT;
                       data_ser <= checksum[7:0];
                    end
                   end else if (pixel_width == 10) begin
                     if (packing == 4) begin
                        // multiple of 4 bytes
                        data_ser <= lsbs;
                        ser_wc <= ser_wc - 1;
                        lsbs <= 0; 
                        packing <= 0;
                        if (ser_wc > 0) begin
                            image_re <= 1;
                        end 
                     end else begin
                        if (image_re) begin
                           lsbs <= lsbs | {6'b0,datar[1:0]} << packing*2;
                           packing <= packing + 1;
                           ser_wc <= ser_wc -1;
                           /* verilator lint_off SELRANGE */
                           // NOTE it's valid when data width is 10
                           data_ser <= datar[9:2]; 
                           /* verilator lint_on SELRANGE */
                           if (packing == 3 || ser_wc == 0) begin
                             image_re <= 0; // don't read a byte this time next time send lsbs
                           end
                        end else begin
                            substate <= ST_HS_EOT;
                            data_ser <= checksum[7:0];
                        end

                     end
                   end else begin
                     //assert(0); // error case 
                     $display ( "Error Case - mipi cis2 ser" );
                   end
                   
                end
            end
          end else if (substate == ST_HS_EOT) begin
             data_ser <= checksum[15:8]; 
             //hs_req <= 0;
             substate <= ST_IDLE;
          end
       end
   end

   //wire hs_req_phy = hs_req || hs_req_s; // hold high for checksum

   mipi_phy_ser 
    mipi_phy_ser (
       .resetb      (resetb),
       .enable      (enable),

       .hs_req      (hs_req),
       .re          (phy_re),
       .data        (data_ser),
       .clk_hs      (clk_hs),
       .clk_ls      (clk_ls),


       .mcp         (mcp),
       .mcn         (mcn),
       .mdp         (mdp),
       .mdn         (mdn),

       .mdp_lp      (mdp_lp),
       .mdn_lp      (mdn_lp)

   );


endmodule
