`timescale 1ns/1ps
//============================================================================
// fp_add_sub : Bo cong/tru so cham dong IEEE-754 single precision (32-bit)
//   sub = 0  ->  result = a + b
//   sub = 1  ->  result = a - b
//   To hop (combinational). Lam tron: round-to-nearest-even (RNE).
//   Xu ly: so binh thuong, so 0, +/-Inf, NaN.
//   Denormal: xu ly don gian (flush-to-zero khi underflow).
//============================================================================
module fp_add_sub (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        sub,
    output reg  [31:0] result
);
    localparam [31:0] QNAN = 32'h7FC00000;   // quiet NaN

    //------------------------------------------------------------------
    // 1) UNPACK: tach sign / exponent / fraction
    //------------------------------------------------------------------
    wire        sa = a[31];
    wire        sb = b[31] ^ sub;            // dao dau cua b khi tru
    wire [7:0]  ea = a[30:23];
    wire [7:0]  eb = b[30:23];
    wire [22:0] fa = a[22:0];
    wire [22:0] fb = b[22:0];

    // significand co bit an (hidden bit). Denormal -> hidden bit = 0
    wire [23:0] sig_a = {(ea != 8'd0), fa};
    wire [23:0] sig_b = {(eb != 8'd0), fb};

    // co cac truong hop dac biet
    wire a_nan = (ea == 8'hFF) && (fa != 0);
    wire b_nan = (eb == 8'hFF) && (fb != 0);
    wire a_inf = (ea == 8'hFF) && (fa == 0);
    wire b_inf = (eb == 8'hFF) && (fb == 0);

    // chon toan hang co do lon lon hon (big) va nho hon (small)
    wire a_ge_b = (ea > eb) || ((ea == eb) && (sig_a >= sig_b));
    wire        s_big = a_ge_b ? sa    : sb;
    wire        s_sml = a_ge_b ? sb    : sa;
    wire [7:0]  e_big = a_ge_b ? ea    : eb;
    wire [7:0]  e_sml = a_ge_b ? eb    : ea;
    wire [23:0] m_big = a_ge_b ? sig_a : sig_b;
    wire [23:0] m_sml = a_ge_b ? sig_b : sig_a;
    wire [7:0]  ediff = e_big - e_sml;       // chenh lech mu

    //------------------------------------------------------------------
    // Ham dem so bit 0 dau de chuan hoa (tinh so lan dich trai)
    //------------------------------------------------------------------
    function [4:0] norm_shift;
        input [26:0] v;
        integer i;
        begin
            norm_shift = 5'd27;              // 27 = toan bo bang 0
            for (i = 0; i < 27; i = i + 1)
                if (v[i]) norm_shift = 26 - i;  // lan gan cuoi = bit 1 cao nhat
        end
    endfunction

    // bien lam viec (khung 27 bit: [26:3] = significand 24 bit, [2:0] = G/R/S)
    reg  [26:0] big_ext, sml_ext, sml_sh;
    reg         sticky;
    reg  [27:0] sum;                          // them 1 bit MSB de bat carry
    reg  [27:0] sig_c, sig_n;
    reg  signed [10:0] exp_c, exp_n, fexp;
    reg  [4:0]  lsh;
    reg  [24:0] sig_r;
    reg  [23:0] fsig;
    reg         g, r, st, l, rup;

    always @(*) begin
        //--------------------------------------------------------------
        // 2) ALIGN: dich phai significand nho hon, gom bit roi vao sticky
        //--------------------------------------------------------------
        big_ext = {m_big, 3'b000};
        sml_ext = {m_sml, 3'b000};
        if (ediff >= 27) begin
            sticky    = |m_sml;               // tat ca thanh sticky
            sml_sh    = {26'b0, sticky};
        end else begin
            if (ediff == 0) sticky = 1'b0;
            else            sticky = |(sml_ext & (({27{1'b1}}) >> (27 - ediff)));
            sml_sh     = sml_ext >> ediff;
            sml_sh[0]  = sml_sh[0] | sticky;
        end

        //--------------------------------------------------------------
        // 3) ADD/SUB phan do lon
        //--------------------------------------------------------------
        if (s_big == s_sml)
            sum = {1'b0, big_ext} + {1'b0, sml_sh};
        else
            sum = {1'b0, big_ext} - {1'b0, sml_sh};

        //--------------------------------------------------------------
        // 4) NORMALIZE
        //--------------------------------------------------------------
        // 4a) carry-out -> dich phai 1
        if (sum[27]) begin
            sig_c    = sum >> 1;
            sig_c[0] = sig_c[0] | sum[0];
            exp_c    = $signed({3'b0, e_big}) + 11'sd1;
        end else begin
            sig_c    = sum;
            exp_c    = $signed({3'b0, e_big});
        end
        // 4b) dich trai cho den khi bit 26 = 1
        if (sig_c[26]) begin
            sig_n = sig_c; exp_n = exp_c; lsh = 5'd0;
        end else begin
            lsh = norm_shift(sig_c[26:0]);
            if (lsh == 5'd27) begin
                sig_n = 28'b0; exp_n = 11'sd0;      // ket qua bang 0
            end else begin
                sig_n = sig_c << lsh;
                exp_n = exp_c - $signed({6'b0, lsh});
            end
        end

        //--------------------------------------------------------------
        // 5) ROUND (round-to-nearest-even)
        //--------------------------------------------------------------
        l   = sig_n[3];                       // LSB cua significand giu lai
        g   = sig_n[2];                       // guard
        r   = sig_n[1];                       // round
        st  = sig_n[0];                       // sticky
        rup = g & (r | st | l);
        sig_r = {1'b0, sig_n[26:3]} + rup;    // 25 bit de bat tran khi lam tron
        if (sig_r[24]) begin
            fsig = sig_r[24:1];
            fexp = exp_n + 11'sd1;
        end else begin
            fsig = sig_r[23:0];
            fexp = exp_n;
        end

        //--------------------------------------------------------------
        // 6) PACK + xu ly truong hop dac biet
        //--------------------------------------------------------------
        if (a_nan || b_nan)
            result = QNAN;
        else if (a_inf && b_inf)
            result = (sa != sb) ? QNAN : {sa, 8'hFF, 23'b0};  // Inf - Inf = NaN
        else if (a_inf)
            result = {sa, 8'hFF, 23'b0};
        else if (b_inf)
            result = {sb, 8'hFF, 23'b0};
        else if (sig_n == 28'b0)
            result = 32'h00000000;            // +0
        else if (fexp >= 11'sd255)
            result = {s_big, 8'hFF, 23'b0};   // tran -> Inf
        else if (fexp <= 11'sd0)
            result = {s_big, 31'b0};          // underflow -> 0 (don gian)
        else
            result = {s_big, fexp[7:0], fsig[22:0]};
    end
endmodule
