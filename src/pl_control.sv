// =============================================================================
// pl_control.sv
// Unidade de Controle Principal -- RV32I pipelined (P&H secao 4.4)
//
// Decodifica o opcode de 7 bits (estagio ID) e gera os sinais de controle
// que serao propagados pelos registradores de pipeline.
//
// Instrucoes suportadas:
//   R-type  (0110011): add, sub, or, and, slt, xor, sll, srl, sra, sltu
//   I-type  (0010011): addi, andi, ori, slti, slli, srli, srai
//   I-type  (0000011): lb, lh, lw, lbu, lhu
//   S-type  (0100011): sb, sh, sw
//   B-type  (1100011): beq, bne, blt, bge, bltu, bgeu
//   J-type  (1101111): jal
//   I-type  (1100111): jalr
//   U-type  (0110111): lui
//   U-type  (0010111): auipc
//
// Convencoes principais:
//   ALUSrc    : 0=registrador, 1=imediato
//   ALUASrc   : 0=rs1, 1=PC (AUIPC)
//   ResultSrc : 00=ALU, 01=memoria, 10=PC+4, 11=imediato (LUI)
//   ALUOp     : 00=ADD fixo, 01=branch, 10=R-type, 11=I-type aritmetico
// =============================================================================

`timescale 1ns / 1ps

module pl_control (
    input  logic [6:0] Opcode,
    output logic       ALUSrc,
    output logic       MemtoReg,
    output logic       RegWrite,
    output logic       MemRead,
    output logic       MemWrite,
    output logic       Branch,
    output logic       Jump,
    output logic       JumpReg,
    output logic       ALUASrc,
    output logic [1:0] ResultSrc,
    output logic [1:0] ALUOp
);

    localparam R_TYPE = 7'b0110011;
    localparam I_TYPE = 7'b0010011;
    localparam LOAD   = 7'b0000011;
    localparam STORE  = 7'b0100011;
    localparam BRANCH = 7'b1100011;
    localparam JAL    = 7'b1101111;
    localparam JALR   = 7'b1100111;
    localparam LUI    = 7'b0110111;
    localparam AUIPC  = 7'b0010111;

    always_comb begin
        ALUSrc   = 1'b0;
        MemtoReg = 1'b0;
        RegWrite = 1'b0;
        MemRead  = 1'b0;
        MemWrite = 1'b0;
        Branch   = 1'b0;
        Jump     = 1'b0;
        JumpReg  = 1'b0;
        ALUASrc  = 1'b0;
        ResultSrc = 2'b00;
        ALUOp    = 2'b00;

        case (Opcode)
            R_TYPE: begin
                ALUSrc   = 1'b0;
                MemtoReg = 1'b0;
                RegWrite = 1'b1;
                ALUOp    = 2'b10;
            end
            I_TYPE: begin
                ALUSrc   = 1'b1;
                MemtoReg = 1'b0;
                RegWrite = 1'b1;
                ALUOp    = 2'b11;
            end
            LOAD: begin
                ALUSrc   = 1'b1;
                MemtoReg = 1'b1;
                RegWrite = 1'b1;
                MemRead  = 1'b1;
                ResultSrc = 2'b01;
                ALUOp    = 2'b00;
            end
            STORE: begin
                ALUSrc   = 1'b1;
                MemWrite = 1'b1;
                ALUOp    = 2'b00;
            end
            BRANCH: begin
                Branch   = 1'b1;
                ALUOp    = 2'b01;
            end
            JAL: begin
                RegWrite  = 1'b1;
                Jump      = 1'b1;
                ResultSrc = 2'b10;
            end
            JALR: begin
                ALUSrc    = 1'b1;
                RegWrite  = 1'b1;
                Jump      = 1'b1;
                JumpReg   = 1'b1;
                ResultSrc = 2'b10;
                ALUOp     = 2'b00;
            end
            LUI: begin
                RegWrite  = 1'b1;
                ResultSrc = 2'b11;
            end
            AUIPC: begin
                ALUSrc    = 1'b1;
                ALUASrc   = 1'b1;
                RegWrite  = 1'b1;
                ALUOp     = 2'b00;
            end
            default: ; // sinais permanecem em zero (seguro)
        endcase
    end

endmodule
