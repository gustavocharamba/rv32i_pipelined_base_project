// =============================================================================
// pl_alu_ctrl.sv
// Unidade de Controle da ALU -- RV32I pipelined (P&H secao 4.4)
//
// Entradas (do estagio EX -- registrador ID/EX):
//   ALUOp[1:0] : codigo do controlador principal
//     2'b00 : Load/Store  -> forcar ADD
//     2'b01 : Branch BEQ  -> forcar SUB
//     2'b10 : R-type      -> decodificar via Funct3/Funct7
//     2'b11 : I_TYPE      -> decodificar via Funct3/Funct7
//   Funct7[6:0], Funct3[2:0] : campos da instrucao
//
// Saida Operation[3:0] -> pl_alu.sv:
//   4'd01 ADD   4'd02 SUB   4'd04 OR    4'd05 AND
//   4'd06 XOR   4'd07 SLL   4'd08 SRL   4'd09 SRA
//   4'd11 SLT   4'd12 SLTU
// =============================================================================

`timescale 1ns / 1ps

module pl_alu_ctrl (
    input  logic [1:0] ALUOp,
    input  logic [6:0] Funct7,
    input  logic [2:0] Funct3,
    output logic [3:0] Operation
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
        case (ALUOp)
            2'b00: Operation = ALU_ADD;   // Load / Store -> ADD

            2'b01: Operation = ALU_SUB;   // Branch BEQ  -> SUB

            2'b10: begin                // R-type: decodificar Funct
                case (Funct3)
                    3'h0: Operation = Funct7[5] ? ALU_SUB : ALU_ADD; // SUB ou ADD
                    3'h1: Operation = ALU_SLL;
                    3'h2: Operation = ALU_SLT;
                    3'h3: Operation = ALU_SLTU;
                    3'h4: Operation = ALU_XOR;
                    3'h5: Operation = Funct7[5] ? ALU_SRA : ALU_SRL;
                    3'h6: Operation = ALU_OR;
                    3'h7: Operation = ALU_AND;
                    default: Operation = ALU_ADD;
                endcase
            end

            2'b11: begin                // I_TYPE: addi/andi/ori/slti/slli/srli/srai
                case (Funct3)
                    3'h0: Operation = ALU_ADD; // ADDI
                    3'h1: Operation = ALU_SLL; // SLLI
                    3'h2: Operation = ALU_SLT; // SLTI
                    3'h5: Operation = Funct7[5] ? ALU_SRA : ALU_SRL; // SRAI ou SRLI
                    3'h6: Operation = ALU_OR;  // ORI
                    3'h7: Operation = ALU_AND; // ANDI
                    default: Operation = ALU_ADD;
                endcase
            end

            default: Operation = ALU_ADD;
        endcase
    end

endmodule
