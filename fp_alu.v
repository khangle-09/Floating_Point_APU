`timescale 1ns/1ps
//============================================================================
// fp_alu : ALU so cham dong IEEE-754 single precision (32-bit)
//   op = 000 : ADD  (a + b)
//   op = 001 : SUB  (a - b)
//   op = 010 : MUL  (a * b)
//   op = 011 : DIV  (a / b)
//   Cac op khac -> 0
//
//   Co status flag: nan / inf / zero (suy ra tu ket qua).
//============================================================================
module fp_alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  op,
    output reg  [31:0] result,
    output wire        nan,
    output wire        inf,
    output wire        zero
);
    wire [31:0] r_add, r_sub, r_mul, r_div;

    fp_add_sub u_add (.a(a), .b(b), .sub(1'b0), .result(r_add));
    fp_add_sub u_sub (.a(a), .b(b), .sub(1'b1), .result(r_sub));
    fp_mul     u_mul (.a(a), .b(b),             .result(r_mul));
    fp_div     u_div (.a(a), .b(b),             .result(r_div));

    always @(*) begin
        case (op)
            3'b000:  result = r_add;
            3'b001:  result = r_sub;
            3'b010:  result = r_mul;
            3'b011:  result = r_div;
            default: result = 32'h00000000;
        endcase
    end

    assign nan  = (result[30:23] == 8'hFF) && (result[22:0] != 0);
    assign inf  = (result[30:23] == 8'hFF) && (result[22:0] == 0);
    assign zero = (result[30:23] == 8'h00) && (result[22:0] == 0);
endmodule
