// =============================================================================
// pl_alu.sv
// Unidade Logica e Aritmetica de 32 bits -- RV32I pipelined
//
// Codificacao de operacao (Operation[3:0]):
//   4'd01 : ADD   -- adicao
//   4'd02 : SUB   -- subtracao (BEQ usa Zero)
//   4'd04 : OR    -- OU bit a bit
//   4'd05 : AND   -- E bit a bit
//   4'd06 : XOR   -- OU exclusivo bit a bit
//   4'd07 : SLL   -- deslocamento logico a esquerda
//   4'd08 : SRL   -- deslocamento logico a direita
//   4'd09 : SRA   -- deslocamento aritmetico a direita
//   4'd11 : SLT   -- set-less-than com sinal
//   4'd12 : SLTU  -- set-less-than sem sinal
// =============================================================================

`timescale 1ns / 1ps

module pl_alu (
    input  logic [31:0] SrcA,
    input  logic [31:0] SrcB,
    input  logic [3:0]  Operation,
    output logic [31:0] ALUResult,
    output logic        Zero
);

    localparam ALU_ADD  = 4'd01;
    localparam ALU_SUB  = 4'd02;
    localparam ALU_OR   = 4'd04;
    localparam ALU_AND  = 4'd05;
    localparam ALU_XOR  = 4'd06;
    localparam ALU_SLL  = 4'd07;
    localparam ALU_SRL  = 4'd08;
    localparam ALU_SRA  = 4'd09;
    localparam ALU_SLT  = 4'd11;
    localparam ALU_SLTU = 4'd12;

    always_comb begin
        case (Operation)
            ALU_ADD:  ALUResult = SrcA + SrcB;
            ALU_SUB:  ALUResult = SrcA - SrcB;
            ALU_OR:   ALUResult = SrcA | SrcB;
            ALU_AND:  ALUResult = SrcA & SrcB;
            ALU_XOR:  ALUResult = SrcA ^ SrcB;
            ALU_SLL:  ALUResult = SrcA << SrcB[4:0];
            ALU_SRL:  ALUResult = SrcA >> SrcB[4:0];
            ALU_SRA:  ALUResult = $signed(SrcA) >>> SrcB[4:0];
            ALU_SLT:  ALUResult = {31'b0, ($signed(SrcA) < $signed(SrcB))};
            ALU_SLTU: ALUResult = {31'b0, (SrcA < SrcB)};
            default: ALUResult = 32'b0;
        endcase
    end

    assign Zero = (ALUResult == 32'b0);

endmodule
