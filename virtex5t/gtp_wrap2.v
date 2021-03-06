`timescale 1ns / 1ns

// Avnet AES-XLX-V5LXT-PCIE50-G SFP: GTP_Dual_X0Y5
//   CLK_SYNTH0_P connects to MGTREFCLKP_120 (E4)
//   CLK_SYNTH0_N connects to MGTREFCLKN_120 (D4)
// XXX should really set polarity inversion for SFP0 Tx and SFP1 Rx.
//  See UG Table 6, p. 14.  Somehow irrelevant when using 8b/10b?
// The "2" here is to distinguish it from the gtp_wrap used in ORION,
//  which is similar but incompatible.
module gtp_wrap2(
	input  [9:0] txdata0,
	output [9:0] rxdata0,
	output [6:0] rxstatus0,
	output       txstatus0,
	input  [9:0] txdata1,
	output [9:0] rxdata1,
	output [6:0] rxstatus1,
	output       txstatus1,
	output  tx_clk,
	output  rx_clk,
	input   gtp_reset,
	// semantics-free ports, just have to carry the pins around
	// so there's something for the UCF to find?
	input   refclk_p,
	input   refclk_n,
	input   rxn0,
	input   rxp0,
	output  txn0,
	output  txp0,
	input   rxn1,
	input   rxp1,
	output  txn1,
	output  txp1
);

wire refclk;
// UG196 p.51 (IBUFDS example instantiation lies like a rug)
IBUFDS ref_clk_buff(.I(refclk_p), .IB(refclk_n), .O(refclk));

// use GTP clock input from ICS8442, D4/E4
wire tile_refclk=refclk;

// UG196 p. 94 Figure 6-4
wire unbuf_clk;   // tile's REFCLKOUT_OUT
wire bufg_source=unbuf_clk;

BUFG main_clock(.I(bufg_source), .O(tx_clk));  // output used for Tx fabric

// UG196 p. 106, Using the TX Phase-Alignment Circuit to Bypass the TX Buffer
// Of course, none of PLL_DIVSEL_COMM_OUT, PLL_DIVSEL_OUT_0, or
// PLL_DIVSEL_OUT_1 are mentioned anywhere else in the document.
reg pma_align1=0, pma_align2=0;
reg [14:0] pma_counter=0;
always @(posedge tx_clk) begin
	pma_counter <= gtp_reset ? 15'd0 :
		((pma_counter == 15'd32767) ? 15'd32767 : (pma_counter+1'b1));
	pma_align1 <= (pma_counter > 32);
	pma_align2 <= (pma_counter > 64) & (pma_counter < 24576);
end

// XXX need to do something with these eventually
wire rxbufreset0=0;
wire rxbufreset1=0;

// Use the recovered clock for the Rx subsystem
// Ignore serdes #1 for now
wire rxrecclk0, rxrecclk1;
assign rx_clk = rxrecclk0;

// Assemble the 7-bit Rx status word
// XXX Set disparity error to 0 for now (8b10b bypassed) status word to be re-arranged
wire rxdisperr0=0, rxdisperr1=0;
wire       rxnotintable0,     rxnotintable1;
wire       rxbyteisaligned0,  rxbyteisaligned1;
wire [1:0] rxlossofsync0,     rxlossofsync1;
wire [2:0] rxbufstatus0,      rxbufstatus1;
assign rxstatus0 = {rxdisperr0, rxnotintable0, rxlossofsync0[1],
	rxbyteisaligned0, rxbufstatus0};
assign rxstatus1 = {rxdisperr1, rxnotintable1, rxlossofsync1[1],
	rxbyteisaligned1, rxbufstatus1};

// Only one bit of Tx status for now
wire txrundisp0, txrundisp1;
assign txstatus0 = txrundisp0;
assign txstatus1 = txrundisp1;

// Instantiate the GTP_DUAL via the two-layer wrapper generated by
// Xilinx's RocketIO GTP Wizard version 1.8
`ifndef SIMULATE
ROCKETIO_WRAPPER_GTP foo(
	.TILE0_TXDATA0_IN(txdata0[7:0]),
	//.TILE0_TXCHARISK0_IN(txdata0[8]),    //(undefined when 8b10b encoder is bypassed)
	.TILE0_TXCHARDISPVAL0_IN(txdata0[8]),  // new (used to extend the 8-bit interface to a TBI)
	.TILE0_TXCHARDISPMODE0_IN(txdata0[9]), // new (used to extend the 8-bit interface to a TBI)
	.TILE0_TXRESET0_IN(1'b0), // new
	.TILE0_TXRUNDISP0_OUT(txrundisp0),  // new
	.TILE0_TXUSRCLK0_IN(tx_clk),
	.TILE0_TXUSRCLK20_IN(tx_clk),
	.TILE0_TXN0_OUT(txn0),
	.TILE0_TXP0_OUT(txp0),

	.TILE0_LOOPBACK0_IN(3'b0), // new
	.TILE0_RXRECCLK0_OUT(rxrecclk0), // new
	.TILE0_RXDATA0_OUT(rxdata0[7:0]),
	.TILE0_RXCHARISK0_OUT(rxdata0[8]),	// (used to extend the 8-bit interface to a TBI)
	.TILE0_RXDISPERR0_OUT(rxdata0[9]),	// new (used to extend the 8-bit interface to a TBI)
	.TILE0_RXNOTINTABLE0_OUT(rxnotintable0),
	//.TILE0_RXBYTEISALIGNED0_OUT(rxbyteisaligned0),
	//.TILE0_RXLOSSOFSYNC0_OUT(rxlossofsync0),
	.TILE0_RXRESET0_IN(1'b0), // new
	.TILE0_RXBUFRESET0_IN(rxbufreset0),
	.TILE0_RXBUFSTATUS0_OUT(rxbufstatus0),
	.TILE0_RXENMCOMMAALIGN0_IN(1'b1),
	.TILE0_RXENPCOMMAALIGN0_IN(1'b1),
	.TILE0_RXUSRCLK0_IN(rx_clk),
	.TILE0_RXUSRCLK20_IN(rx_clk),
	.TILE0_RXN0_IN(rxn0),
	.TILE0_RXP0_IN(rxp0),

	.TILE0_TXDATA1_IN(txdata1[7:0]),
	//.TILE0_TXCHARISK1_IN(txdata1[8]),	//(undefined when 8b10b encoder is bypassed)
	.TILE0_TXCHARDISPVAL1_IN(txdata1[8]),   // new (used to extend the 8-bit interface to a TBI)
	.TILE0_TXCHARDISPMODE1_IN(txdata1[9]),  // new (used to extend the 8-bit interface to a TBI)
	.TILE0_TXRESET1_IN(1'b0), // new
	.TILE0_TXRUNDISP1_OUT(txrundisp1),  // new
	.TILE0_TXUSRCLK1_IN(tx_clk),
	.TILE0_TXUSRCLK21_IN(tx_clk),
	.TILE0_TXN1_OUT(txn1),
	.TILE0_TXP1_OUT(txp1),

	.TILE0_LOOPBACK1_IN(3'b0), // new
	.TILE0_RXRECCLK1_OUT(rxrecclk1), // new
	.TILE0_RXDATA1_OUT(rxdata1[7:0]),
	.TILE0_RXCHARISK1_OUT(rxdata1[8]),	// new (used to extend the 8-bit interface to a TBI)
	.TILE0_RXDISPERR1_OUT(rxdata1[9]),	// new (used to extend the 8-bit interface to a TBI)
	.TILE0_RXNOTINTABLE1_OUT(rxnotintable1),
	//.TILE0_RXBYTEISALIGNED1_OUT(rxbyteisaligned1),
	//.TILE0_RXLOSSOFSYNC1_OUT(rxlossofsync1),
	.TILE0_RXRESET1_IN(1'b0), // new
	.TILE0_RXBUFRESET1_IN(rxbufreset1),
	.TILE0_RXBUFSTATUS1_OUT(rxbufstatus1),
	.TILE0_RXENMCOMMAALIGN1_IN(1'b1),
	.TILE0_RXENPCOMMAALIGN1_IN(1'b1),
	.TILE0_RXUSRCLK1_IN(rx_clk),
	.TILE0_RXUSRCLK21_IN(rx_clk),
	.TILE0_RXN1_IN(rxn1),
	.TILE0_RXP1_IN(rxp1),

	.TILE0_CLKIN_IN(tile_refclk),
	.TILE0_GTPRESET_IN(gtp_reset),
	.TILE0_REFCLKOUT_OUT(unbuf_clk)
	//.TILE0_TXENPMAPHASEALIGN_IN(pma_align1),
	//.TILE0_TXPMASETPHASE_IN(pma_align2)
);
`endif

endmodule
