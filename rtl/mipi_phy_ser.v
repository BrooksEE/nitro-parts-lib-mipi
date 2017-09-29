module mipi_phy_ser
    #(parameter MAX_LANES=1)
(

       input resetb,
       input enable,

       input clk_ls,
       input clk_hs,

       input hs_req,
       output reg re,
       input dv,
       input [7:0] data,
       input [2:0] num_active_lanes,

       output reg mcp, // output clock
       output reg mcn,
       output reg [MAX_LANES-1:0] mdp, // output data
       output reg [MAX_LANES-1:0] mdn,

       output reg [MAX_LANES-1:0] mdp_lp, // low power data output
       output reg [MAX_LANES-1:0] mdn_lp
);

  integer i;

    wire clk_ser;
    PLL_sim
       #(.PLL_NAME("phy_8x"))
    pll_ser (
        .input_clk(clk_hs),
        .output_clk(clk_ser),
        .pll_mult(8),
        .pll_div({{29{1'b0}}, num_active_lanes}), //MAX_LANES),
	     .locked(),
	     .debug(0)
    );

    always @(posedge clk_ser or negedge resetb) begin
        if(!resetb) begin
            mcp <= 0;
            mcn <= 1;
        end else begin
            mcp <= !mcp;
            mcn <= mcp;
        end
    end

    parameter ST_STOP = 0, ST_HS_RQST=1, ST_HS_PRPR=2, ST_SOT=3, ST_HST=4, ST_EOT=5, ST_SOUT=6, ST_WAIT=7;
    reg [2:0] state;
    reg [1:0] lp_cnt;
    reg [1:0] lp_cnt_s;
    reg [1:0] lp_cnt_1;
    reg [7:0] data_sync;
    reg [1:0] sotcnt;
    reg timeout;

    always @(posedge clk_hs or negedge resetb) begin
        if (!resetb) begin
           state <= ST_STOP;
           for (i=0;i<num_active_lanes;i=i+1) begin
             mdp_lp[i] <= 1'b1;
             mdn_lp[i] <= 1'b1;
           end
           lp_cnt_s <= 0;
           data_sync <= 0;
           timeout <= 0;
           re <= 0;
           sotcnt <= 0;
        end else begin
            lp_cnt_s <= lp_cnt;
            if (state == ST_STOP) begin
              state <= ST_HS_RQST;
              for (i=0;i<num_active_lanes;i=i+1) begin
                mdp_lp[i] <= 1'b0;
              end
              lp_cnt_1 <= lp_cnt-1;

              //if (hs_req) begin
              //   state <= ST_HS_RQST;
              //   mdp_lp <= 0;
              //   lp_cnt_1 <= lp_cnt-1;
              //end else begin
              //   mdp_lp <= 1;
              //   mdn_lp <= 1;
              //end
            end else if (state == ST_HS_RQST) begin
              if (lp_cnt_s == lp_cnt_1) begin
                for (i=0;i<num_active_lanes;i=i+1) begin
                  mdn_lp[i] <= 1'b0;
                end
                state <= ST_HS_PRPR;
                lp_cnt_1 <= lp_cnt - 1;
                timeout <= 0;
              end
            end else if (state == ST_HS_PRPR) begin
              if (lp_cnt_s == lp_cnt_1) begin
                timeout <= 1;
              end

              if (timeout && hs_req) begin
                // disable low power driver
                // enable hi speed driver
                state <= ST_SOT;
                re <= 1;
                sotcnt <= 0;
              end
            end else if (state <= ST_SOT) begin
              if (sotcnt == num_active_lanes-1) begin
                re <= 1;
                state <= ST_HST;
              end else begin
                sotcnt <= sotcnt + 1;
                re <= 0;
              end
              data_sync <= 8'hb8; // start code, send sot on each lane
            end else if (state == ST_HST) begin
              if (!hs_req) begin
                data_sync <= {8{!data_sync[7]}};  // toggle data lines one more time but then they don't change
                re <= 0;
                state <= ST_EOT;
                lp_cnt_1 <= lp_cnt_s-1;
              end else begin
                  data_sync <= data;
              end
            end else if (state== ST_EOT) begin
              if (lp_cnt_s == lp_cnt_1) begin
//                for (i=0;i<MAX_LANES;i=i+1) begin
//                  mdp_lp[i] <= 1'b1;
//                  mdn_lp[i] <= 1'b1;
//                end
                state <= ST_SOUT;
                lp_cnt_1 <= lp_cnt - 1;
              end
            end else if (state == ST_SOUT) begin
              if (empty) begin
                for (i=0;i<num_active_lanes;i=i+1) begin
                  mdp_lp[i] <= 1'b1;
                  mdn_lp[i] <= 1'b1;
                  state <= ST_WAIT;
                end
              end
            end else if (state==ST_WAIT) begin
              if (lp_cnt_s == lp_cnt_1) begin
                state <= ST_STOP;
              end
            end
        end //reset
    end //always

    // TODO fix timing
    always @(posedge clk_ls or negedge resetb) begin
        if (!resetb) begin
            lp_cnt <= 0;
        end else begin
            lp_cnt <= lp_cnt + 1;
        end
    end

    wire [7:0] data_out;
    wire empty;
    wire wen_d = (state == ST_SOT ||
              state == ST_EOT ||
              state == ST_HST);
    reg wen;
    reg ren;
    wire [3:0] uspace;

    always @(posedge clk_hs) wen <= wen_d;

    fifo_dualclk #(.ADDR_WIDTH(4), .DATA_WIDTH(8)) ser_data_fifo (
        .wclk            (clk_hs),
        .rclk            (clk_ser),
        .we              (wen),
        .re              (ren&~empty),
        .resetb          (resetb),
        .flush           (0),
        .full            (),
        .empty           (empty),
        .wdata           (data_sync),
        .rdata           (data_out),
        .wFreeSpace      (),
        .rUsedSpace      (uspace)
    );

    reg[8*MAX_LANES-1:0] data_shift;
    reg [1:0] serstate;
    reg [2:0] shcnt;
    reg [8*MAX_LANES-1:0] data_hold;
    reg [1:0] loadcnt;

    localparam SST_IDLE = 0, SST_LOAD = 1, SST_SHIFT = 2;

    always @(posedge clk_ser or negedge resetb) begin
      if (~resetb) begin
        serstate <= SST_IDLE;
        ren <= 0;
        data_hold <= 0;
        loadcnt <= 0;
      end else begin
        case (serstate)
          SST_IDLE : begin
              //if (~empty) begin
              if (uspace > 4) begin
                serstate <= SST_LOAD;
                ren <= 1;
                loadcnt <= 0;
              end
            end
          SST_LOAD : begin
              if (~empty) begin
                data_hold[8*loadcnt +:8] <= data_out;
                loadcnt <= loadcnt + 1;
                if (loadcnt == num_active_lanes-1) begin
                  ren <= 0;
                  loadcnt <= 0;
                  serstate <= SST_SHIFT;
                end
              end else begin
                ren <= 0;
                loadcnt <= 0;
                serstate <= SST_IDLE;
              end
            end
          SST_SHIFT : begin
              if (shcnt == 7) begin
                if (~empty) begin
                  serstate <= SST_LOAD;
                  ren <= 1;
                end else begin
                  serstate <= SST_IDLE;
                end
              end
            end
        endcase

      end
    end

    always @(posedge clk_ser or negedge resetb) begin
      if (~resetb) begin
        shcnt <= 0;
        data_shift <= 0;
      end else begin
        if (serstate == SST_IDLE) begin
          shcnt <= 0;
        end else begin
          if (shcnt == 7) begin
            data_shift <= data_hold;
            shcnt <= 0;
          end else begin
            shcnt <= shcnt + 1;
            data_shift <= data_shift >> 1;
          end
        end
        for (i=0; i<num_active_lanes;i=i+1) begin
          mdn[i] <= !data_shift[i*8];
          mdp[i] <= data_shift[i*8];
        end
      end
    end

endmodule
