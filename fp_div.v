`timescale 1ns/1ps
//============================================================================
// fp_div : Bo chia so cham dong IEEE-754 single precision (32-bit)
//   result = a / b
//   To hop, dung restoring division (vong lap unroll -> tong hop duoc).
//   Lam tron RNE. Xu ly 0, Inf, NaN, x/0=Inf, 0/0=NaN, Inf/Inf=NaN.
//   * Luu y FPGA: bo chia to hop nay kha lon. Neu can toi uu tai nguyen,
//     thay bang bo chia tuan tu (FSM nhieu chu ky) hoac IP cua hang.
//============================================================================
module fp_div (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result
);
    localparam [31:0] QNAN = 32'h7FC00000;

    // 1) UNPACK
    wire        sa = a[31];
    wire        sb = b[31];
    wire [7:0]  ea = a[30:23];
    wire [7:0]  eb = b[30:23];
    wire [22:0] fa = a[22:0];
    wire [22:0] fb = b[22:0];
    wire [23:0] sig_a = {(ea != 0), fa};
    wire [23:0] sig_b = {(eb != 0), fb};

    wire a_nan  = (ea==8'hFF)&&(fa!=0);
    wire b_nan  = (eb==8'hFF)&&(fb!=0);
    wire a_inf  = (ea==8'hFF)&&(fa==0);
    wire b_inf  = (eb==8'hFF)&&(fb==0);
    wire a_zero = (ea==0)&&(fa==0);
    wire b_zero = (eb==0)&&(fb==0);

    wire sign = sa ^ sb;                       // 2) XOR dau

    reg [50:0] num, rem_acc, quot;
    reg [26:0] q;
    reg        sticky_rem;
    reg signed [11:0] exp_c, fexp;
    reg [23:0] sig_m, fsig;
    reg g, r, st, l, rup;
    reg [24:0] sig_r;
    integer i;

    always @(*) begin
        //--------------------------------------------------------------
        // 3) Chia significand: q = floor(sig_a * 2^26 / sig_b)
        //    bang restoring division
        //--------------------------------------------------------------
        num     = {sig_a, 26'b0};              // sig_a << 26
        rem_acc = 51'b0;
        quot    = 51'b0;
        for (i = 50; i >= 0; i = i - 1) begin
            rem_acc = (rem_acc << 1) | num[i];
            if (rem_acc >= {27'b0, sig_b}) begin
                rem_acc   = rem_acc - {27'b0, sig_b};
                quot[i]   = 1'b1;
            end
        end
        q          = quot[26:0];
        sticky_rem = |rem_acc;

        // 4) tru mu va cong bias
        exp_c = $signed({4'b0, ea}) - $signed({4'b0, eb}) + 12'sd127;

        //--------------------------------------------------------------
        // 5) NORMALIZE (ti so nam trong (0.5, 2) -> chinh nhieu nhat 1 bit)
        //--------------------------------------------------------------
        if (q[26]) begin                        // ti so >= 1
            sig_m = q[26:3];
            g     = q[2];
            r     = q[1];
            st    = q[0] | sticky_rem;
        end else begin                          // ti so < 1
            sig_m = q[25:2];
            g     = q[1];
            r     = q[0];
            st    = sticky_rem;
            exp_c = exp_c - 12'sd1;
        end

        // 6) ROUND (RNE)
        l   = sig_m[0];
        rup = g & (r | st | l);
        sig_r = {1'b0, sig_m} + rup;
        if (sig_r[24]) begin
            fsig = sig_r[24:1];
            fexp = exp_c + 12'sd1;
        end else begin
            fsig = sig_r[23:0];
            fexp = exp_c;
        end

        // 7) PACK + truong hop dac biet
        if (a_nan || b_nan)
            result = QNAN;
        else if (a_inf && b_inf)
            result = QNAN;                      // Inf / Inf = NaN
        else if (a_zero && b_zero)
            result = QNAN;                      // 0 / 0 = NaN
        else if (a_inf)
            result = {sign, 8'hFF, 23'b0};      // Inf / x = Inf
        else if (b_zero)
            result = {sign, 8'hFF, 23'b0};      // x / 0 = Inf
        else if (b_inf || a_zero)
            result = {sign, 31'b0};             // x/Inf = 0 ; 0/x = 0
        else if (fexp >= 12'sd255)
            result = {sign, 8'hFF, 23'b0};      // tran -> Inf
        else if (fexp <= 12'sd0)
            result = {sign, 31'b0};             // underflow -> 0
        else
            result = {sign, fexp[7:0], fsig[22:0]};
    end
endmodule
