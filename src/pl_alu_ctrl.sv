// =============================================================================
// pl_alu_ctrl.sv
// Unidade de Controle da ALU -- RV32I pipelined (P&H secao 4.4)
//
// Entradas (do estagio EX -- registrador ID/EX):
//   ALUOp[1:0] : codigo do controlador principal
//     2'b00 : Load/Store  -> forcar ADD
//     2'b01 : Branch BEQ  -> forcar SUB
//     2'b10 : R-type      -> decodificar via Funct3/Funct7
//   Funct7[6:0], Funct3[2:0] : campos da instrucao
//
// Saida Operation[3:0] -> pl_alu.sv:
//   4'd01 ADD  4'd02 SUB  4'd04 OR  4'd05 AND  4'd11 SLT
// =============================================================================

`timescale 1ns / 1ps

module pl_alu_ctrl (
    input  logic [1:0] ALUOp,
    input  logic [6:0] Funct7,
    input  logic [2:0] Funct3,
    output logic [3:0] Operation,
    input logic [4:0] LoadControl
);

    always_comb begin
        case (ALUOp)
            2'b00: Operation = 4'd01;   // Load / Store -> ADD
                case(Funct3)
                    3'h0: LoadControl = 00001;
                    3'h1: LoadControl = 00010;
                    3'h2: LoadControl = 00100;
                    3'h3: LoadControl = 01000;
                    3'h4: LoadControl = 10000;
                    default: LoadControl = 00100; // Aleatório 
                endcase


            2'b01: Operation = 4'd02;   // Branch BEQ  -> SUB
                case (Funct3)
                    3'h0: Operation = 4'd02;
                    3'h1: Operation = 4'd02;
                    3'h2: Operation = 4'd10;
                    3'h3: Operation = 4'd10;
                    3'h4: Operation = 4'd11;
                    3'h5: Operation = 4'd11;
                    default: Operation = 4'd02;
                endcase
            2'b10: begin                // R-type: decodificar Funct
                case (Funct3)
                    3'h0: Operation = Funct7[5] ? 4'd02 : 4'd01; // SUB ou ADD
                    3'h6: Operation = 4'd04;  // OR
                    3'h7: Operation = 4'd05;  // AND
                    3'h2: Operation = 4'd06;  // SLT
                    3'h4: Operation = 4'd03;  //XOR IMPLEMENTADO
                    3'h1: Operation = 4'd07;  //SLL IMPLEMENTADO
                    3'h5 : begin 
                        case (Funct7) 
                            7'h00: Operation = 4'd08; //SRL IMPLEMENTADO
                            7'h20: Operation = 4'd09; //SRA IMPLEMENTADO
									 default : Operation = 4'd01;
                        endcase
                    end
                    3'h3: Operation = 4'd10; //SLTU IMPLEMENTADO
                    
                    

                    default: Operation = 4'd01;
                endcase
            end

            2'b11: begin                    //TIPO IMEADIATO IMPLEMENTADO
                case (Funct3)
                    3'h0: Operation = 4'd01; //ADDI IMPLEMENTADO
                    3'h6: Operation = 4'd04;  // ORI IMPLEMENTADO
                    3'h7: Operation = 4'd05;  // ANDI IMPLEMENTADO
                    3'h2: Operation = 4'd06;  // SLTI IMPLEMENTADO
                    3'h1: Operation = 4'd07;  //SLLI IMPLEMENTADO
                    3'h5 : begin 
                        case (Funct7) 
                            7'h00: Operation = 4'd08; //SRLI IMPLEMENTADO
                            7'h20: Operation = 4'd09; //SRAI IMPLEMENTADO
									 default: Operation = 4'd01;
                        endcase
                    end
						default: Operation = 4'd01;
                endcase
            end

            default: Operation = 4'd01;
        endcase
    end

endmodule
