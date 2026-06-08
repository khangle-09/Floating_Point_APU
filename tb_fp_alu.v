`timescale 1ns/1ps
//============================================================================
// tb_fp_alu : Testbench tu kiem tra cho fp_alu (chay tren ModelSim)
//   Bien dich:  vlog fp_add_sub.v fp_mul.v fp_div.v fp_alu.v tb_fp_alu.v
//   Mo phong :  vsim -c tb_fp_alu -do "run -all; quit"
//
//   Bang gia tri IEEE-754 single (tham khao):
//     1.0 = 32'h3F800000     2.0 = 32'h40000000     3.0 = 32'h40400000
//     6.0 = 32'h40C00000     0.5 = 32'h3F000000    -1.5 = 32'hBFC00000
//     +Inf= 32'h7F800000     NaN = 32'h7FC00000     +0  = 32'h00000000
//============================================================================
module tb_fp_alu;
    reg  [31:0] a, b;
    reg  [2:0]  op;
    wire [31:0] result;
    wire nan, inf, zero;
    integer errors = 0;

    fp_alu dut (.a(a), .b(b), .op(op),
                .result(result), .nan(nan), .inf(inf), .zero(zero));

    // op codes
    localparam ADD = 3'b000, SUB = 3'b001, MUL = 3'b010, DIV = 3'b011;

    task check;
        input [127:0] name;     // ten test (chuoi)
        input [31:0]  exp;      // gia tri ky vong
        begin
            #1;
            if (result === exp)
                $display("PASS  %-10s op=%b a=%h b=%h => %h",
                         name, op, a, b, result);
            else begin
                $display("FAIL  %-10s op=%b a=%h b=%h => got %h  exp %h",
                         name, op, a, b, result, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        a=32'h3F800000; b=32'h3F800000; op=ADD; check("1+1",      32'h40000000);
        a=32'h3F800000; b=32'h40000000; op=ADD; check("1+2",      32'h40400000);
        a=32'h40400000; b=32'h3F800000; op=SUB; check("3-1",      32'h40000000);
        a=32'hBFC00000; b=32'h3FC00000; op=ADD; check("-1.5+1.5", 32'h00000000);
        a=32'h40000000; b=32'h40400000; op=MUL; check("2*3",      32'h40C00000);
        a=32'h40C00000; b=32'h40000000; op=DIV; check("6/2",      32'h40400000);
        a=32'h3F800000; b=32'h40000000; op=DIV; check("1/2",      32'h3F000000);
        a=32'h3F800000; b=32'h40400000; op=DIV; check("1/3",      32'h3EAAAAAB);
        a=32'h7F800000; b=32'h3F800000; op=ADD; check("inf+1",    32'h7F800000);
        a=32'h3F800000; b=32'h00000000; op=DIV; check("1/0",      32'h7F800000);
        a=32'h00000000; b=32'h7F800000; op=MUL; check("0*inf",    32'h7FC00000);
        a=32'h7FC00000; b=32'h3F800000; op=ADD; check("nan+1",    32'h7FC00000);

        $display("--------------------------------------------------");
        if (errors == 0) $display(">>> TAT CA TEST DEU PASS <<<");
        else             $display(">>> CO %0d TEST FAIL <<<", errors);
        $finish;
    end
endmodule
