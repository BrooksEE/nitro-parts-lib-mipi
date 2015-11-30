module mipi_phy_ser 
    #(parameter NUM_DATA_LANES=1)
(

       input resetb,
       input enable,

       input clk_ls,
       input clk_hs,

       input hs_req,
       output reg re,
       input [7:0] data,


       output reg mcp, // output clock
       output reg mcn, 
       output reg mdp, // output data 
       output reg mdn, 

       output reg mdp_lp, // low power data output
       output reg mdn_lp
);

    wire clk_ser;
    PLL_sim pll_ser (
        clk_hs,
        clk_ser,
        8,
        1
    );

    parameter ST_STOP = 0, ST_HS_RQST=1, ST_HS_PRPR=2, ST_SOT=3, ST_HST=4, ST_EOT=5, ST_WAIT=6;
    reg [2:0] state;
    reg [1:0] lp_cnt;
    reg [1:0] lp_cnt_s;
    reg [1:0] lp_cnt_1;
    reg [7:0] data_sync;
    reg timeout;

    always @(posedge clk_hs or negedge resetb) begin
        if (!resetb) begin
           state <= ST_STOP; 
           mdp_lp <= 1;
           mdn_lp <= 1;
           lp_cnt_s <= 0;
           data_sync <= 0;
           timeout <= 0;
           re <= 0;
        end else begin
           lp_cnt_s <= lp_cnt;
           if (state == ST_STOP) begin
              
              state <= ST_HS_RQST;
              mdp_lp <= 0;
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
                 mdn_lp <= 0;
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
              end
           end else if (state <= ST_SOT) begin
              state <= ST_HST;
              data_sync <= 8'hb8; // start code
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
                mdp_lp <= 1;
                mdn_lp <= 1;
                state <= ST_WAIT;
                lp_cnt_1 <= lp_cnt - 1;
              end
           end else if (state==ST_WAIT) begin
                if (lp_cnt_s == lp_cnt_1) begin
                    state <= ST_STOP;
                end
           end
        end
    end

    // TODO fix timing
    always @(posedge clk_ls or negedge resetb) begin
        if (!resetb) begin
            lp_cnt <= 0;
        end else begin
            lp_cnt <= lp_cnt + 1;
        end
    end


    always @(posedge clk_ser or negedge resetb) begin
        if(!resetb) begin
            mcp <= 0;
            mcn <= 0;
        end else begin
            mcp <= !mcp;
            mcn <= mcp;
        end
    end

    reg [2:0] pos;
    reg[7:0] data_shift;
    reg [2:0] state_s;

    always @(posedge clk_ser or negedge resetb) begin
        if(!resetb) begin
            pos <= 0;
            mdn <= 0;
            mdp <= 0;
            data_shift <= 0;
            state_s <= 0; 
        end else begin
            state_s <= state;
            if (state_s == ST_SOT || 
                state_s == ST_EOT ||
                state_s == ST_HST) begin
                pos <= pos + 1;
                if(pos == 7) begin
                    data_shift <= data_sync;
                end else begin
                    data_shift <= data_shift >> 1;
                end
                mdn <= !data_shift[0];
                mdp <= data_shift[0];
            end else begin
                pos <= 0;
            end
        end
    end


endmodule
