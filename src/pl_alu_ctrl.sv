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
    output logic [4:0] LoadControl
);

    always_comb begin
        Operation = 4'd01;
        LoadControl = 5'b00100; //lw normal
        case (ALUOp)
            2'b00: begin
                Operation = 4'd01;   // Load / Store -> ADD
                case(Funct3)
                    3'h0: LoadControl = 5'b00001; //LB
                    3'h1: LoadControl = 5'b00010; //LH
                    3'h2: LoadControl = 5'b00100; //LW
                    3'h4: LoadControl = 5'b01000; //LBU
                    3'h5: LoadControl = 5'b10000; //LHU
                    default: LoadControl = 5'b00100; // Aleatório 
                endcase
            end
            2'b01: begin
                Operation = 4'd02;   // Branch BEQ  -> SUB
                case (Funct3)
                    3'h0: Operation = 4'd02; //BEQ
                    3'h1: Operation = 4'd02; //BNE
                    3'h4: Operation = 4'd10; //BLT
                    3'h5: Operation = 4'd10; //BGE
                    3'h6: Operation = 4'd11; //BLTU
                    3'h7: Operation = 4'd11; //BGEU
                    default: Operation = 4'd02;
                endcase
            end
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
                    3'h3: Operation = 4'd11; //SLTU IMPLEMENTADO
                    
                    

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
        endcase
    end

endmodule
