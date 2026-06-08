`timescale 1ns/1ps
//============================================================================
// fp_mul : Bo nhan so cham dong IEEE-754 single precision (32-bit)
//   result = a * b
//   To hop. Lam tron RNE. Xu ly 0, Inf, NaN, 0*Inf=NaN.
//============================================================================
module fp_mul (
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

    reg [47:0] prod;                           // 24 x 24 = 48 bit
    reg signed [11:0] exp_sum, fexp;
    reg [23:0] sig_m, fsig;
    reg g, r, st, l, rup;
    reg [24:0] sig_r;

    always @(*) begin
        // 3) cong mu va tru bias ; 4) nhan significand
        prod    = sig_a * sig_b;
        exp_sum = $signed({4'b0, ea}) + $signed({4'b0, eb}) - 12'sd127;

        // 5) NORMALIZE (tich nam trong [2^46, 2^48) -> bit cao nhat la 46 hoac 47)
        if (prod[47]) begin
            sig_m   = prod[47:24];
            g       = prod[23];
            r       = prod[22];
            st      = |prod[21:0];
            exp_sum = exp_sum + 12'sd1;
        end else begin
            sig_m   = prod[46:23];
            g       = prod[22];
            r       = prod[21];
            st      = |prod[20:0];
        end

        // 6) ROUND (RNE)
        l   = sig_m[0];
        rup = g & (r | st | l);
        sig_r = {1'b0, sig_m} + rup;
        if (sig_r[24]) begin
            fsig = sig_r[24:1];
            fexp = exp_sum + 12'sd1;
        end else begin
            fsig = sig_r[23:0];
            fexp = exp_sum;
        end

        // 7) PACK + truong hop dac biet
        if (a_nan || b_nan)
            result = QNAN;
        else if ((a_inf && b_zero) || (b_inf && a_zero))
            result = QNAN;                      // 0 * Inf = NaN
        else if (a_inf || b_inf)
            result = {sign, 8'hFF, 23'b0};
        else if (a_zero || b_zero)
            result = {sign, 31'b0};
        else if (fexp >= 12'sd255)
            result = {sign, 8'hFF, 23'b0};      // tran -> Inf
        else if (fexp <= 12'sd0)
            result = {sign, 31'b0};             // underflow -> 0
        else
            result = {sign, fexp[7:0], fsig[22:0]};
    end
endmodule
