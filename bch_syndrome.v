`timescale 1ns / 1ps

module dsynN #(
	parameter M = 4,
	parameter T = 3,
	parameter IDX = 0
) (
	input clk,
	input ce,
	input pe,
	input din,
	output reg [M-1:0] synN = 0
);
	`include "bch_syndrome.vh"

	localparam TCQ = 1;

	genvar bit_pos;

	if (syndrome_method(M, T, idx2syn(M, IDX)) == 0) begin
	/* First method */
		for (bit_pos = 0; bit_pos < M; bit_pos = bit_pos + 1) begin : first
			always @(posedge clk) begin
				if (pe)
					synN[bit_pos] <= #TCQ bit_pos ? 1'b0 : din;
				else if (ce)
					synN[bit_pos] <= #TCQ
						^(synN & first_way_terms(M, idx2syn(M, IDX), bit_pos)) ^
						(bit_pos ? 0 : din);
			end
		end
	end else begin
		/* Second method */
		always @(posedge clk) begin
			if (pe)
				synN <= #TCQ {{M-1{1'b0}}, din};
			else if (ce)
				synN <= #TCQ {synN[0+:syndrome_size(M, idx2syn(M, IDX))-1], din} ^
					(syndrome_poly(M, idx2syn(M, IDX)) & {M{synN[syndrome_size(M, idx2syn(M, IDX))-1]}});
		end
	end
endmodule

module bch_syndrome #(
	parameter M = 4,
	parameter T = 3		/* Correctable errors */
) (
	input clk,
	input ce,
	input pe,
	input snce,
	input din,
	output [2*T*M-1:M] out,
	output reg [(2*T-1)*M-1:0] snNout = 0
);

`include "bch_syndrome.vh"

localparam TCQ = 1;

genvar i;
genvar j;
genvar bit_pos;
genvar idx;
genvar syn_done;

localparam SYN_COUNT = syndrome_count(M, T);
wire [SYN_COUNT*M-1:0] syndromes;

/* LFSR registers */
generate
	for (idx = 0; idx < SYN_COUNT; idx = idx + 1) begin : syndrome_gen
		dsynN #(M, T, idx) u_syn(
			.clk(clk),
			.ce(ce),
			.pe(pe),
			.din(din),
			.synN(syndromes[idx*M+:M])
		);
	end
endgenerate

/* Data output */
genvar dat;
for (dat = 1; dat < 2 * T; dat = dat + 1) begin : assign_dat
	if (syndrome_method(M, T, dat2syn(M, dat)) == 0)
		/* First method */
		assign out[dat*M+:M] = syndromes[dat2idx(M, dat)*M+:M];
	else begin
		/* Second method */
		for (bit_pos = 0; bit_pos < M; bit_pos = bit_pos + 1) begin : second
			assign out[dat*M+bit_pos] =
				^(syndromes[dat2idx(M, dat)*M+:M] & second_way_terms(M, dat, bit_pos));
		end
	end
end


/* Syndrome shuffling */
/* snN drdce */
generate
	for (i = 0; i < 2*T-1; i = i + 1) begin : s
		if (i == T + 1 && T < 4) begin
			always @(posedge clk)
				if (pe)
					snNout[i*M+:M] <= #TCQ out[(3*T-i-1)*M+:M];
		end else begin
			always @(posedge clk)
				if (snce)				/* xN dmul21 */
					snNout[i*M+:M] <= #TCQ pe ? out[M*((2*T+1-i)%(2*T-1)+1)+:M] : snNout[M*((i+(2*T-3))%(2*T-1))+:M];
		end
	end
endgenerate


endmodule
