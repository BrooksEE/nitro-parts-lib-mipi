

module mipi_csi2_ser
   (

       input resetb,
       input enable,

       input pixclk,
       input lp_clk_div, // lp mipi mode can run max 10 mhz

       input [9:0] data,
       input vsync,
       input href,
       
       output mcp, // output clock
       output mcn, 
       output mdp, // output data 
       output mdn, 

       output mdp_lp, // low power data output
       output mdn_lp
   );

    reg mcpr, mcnr, mdpr, mdnr, mdp_lpr, mdn_lpr;
    always @(*) begin
       if (!resetb || !enable) begin
         mcp = 1'bz;
         mcn = 1'bz;
         mdp = 1'bz;
         mdn = 1'bz;
         mdp_lp = 1'bz;
         mdn_lp = 1'bz;
       end else begin
         mdp = mdpr;
         mdn = mdnr;
         mcp = mcpr;
         mcn = mcnr;
         mdp_lp = mdp_lpr;
         mdn_lp = mdn_lpr;
       end
    end


    always @(posedge pixclk or negedge pixclk or negedge resetb) begin
        if (!resetb) 
        // test clock output
        mcpr <= pixclk;
        mcpr <= !pixclk;

        mdpr <= 0;
        mdnr <= 0;
        mdp_lpr <= 1;
        mdn_lpr <= 1;
    end


endmodule
