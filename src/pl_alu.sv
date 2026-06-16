// =============================================================================
// pl_alu.sv
// Unidade Logica e Aritmetica de 32 bits -- RV32I pipelined
//
// Codificacao de operacao (Operation[3:0]):
//   4'd01 : ADD  -- adicao com sinal
//   4'd02 : SUB  -- subtracao com sinal  (BEQ usa Zero)
//   4'd04 : OR   -- OU bit a bit
//   4'd05 : AND  -- E bit a bit
//   4'd11 : SLT  -- set-less-than com sinal
// =============================================================================

`timescale 1ns / 1ps

module pl_alu (
    input  logic [31:0] SrcA,
    input  logic [31:0] SrcB,
    input  logic [3:0]  Operation,
    input  logic [2:0] Funct3, // passa o func3 para decidir o beq
    output logic [31:0] ALUResult,
    output logic        Zero
);

    always_comb begin
        case (Operation)
            4'd01:   ALUResult = $signed(SrcA) + $signed(SrcB);
            4'd02:   ALUResult = $signed(SrcA) - $signed(SrcB);
            4'd03:   ALUResult = SrcA ^ SrcB; //XOR IMPLEMENTADO
            4'd04:   ALUResult = SrcA | SrcB; // ORI
            4'd05:   ALUResult = SrcA & SrcB; // ANDI
            4'd06:   ALUResult = 32'($signed(SrcA) < $signed(SrcB));
            4'd07:   ALUResult = SrcA << SrcB[4:0]; //SLL IMPLEMENTADO
            4'd08:   ALUResult = SrcA >> SrcB[4:0]; // SRL IMPLEMENTADO
            4'd09:   ALUResult = $signed(SrcA) >>> SrcB[4:0]; //SRA IMPLEMENTADO
            4'd10:   ALUResult = ($signed(SrcA) < $signed(SrcB)) ? 32'd1 : 32'd0;
            4'd11:   ALUResult = 32'(SrcA < SrcB); //SLTU IMPLEMENTADO
            default: ALUResult = 32'b0;
        endcase
    end

    always_comb begin
        case (Funct3) begin                       // Zero é o sinal para ver se deve ou não o branch ser tomado
            3'h0: Zero = (ALUResult == 32'b0);
            3'h1: Zero = !(ALUResult == 32'b0); 
            3'h4: Zero = (ALUResult == 32'b1);
            3'h5: Zero = !(ALUResult == 32'b1);
            3'h6: Zero = (ALUResult == 32'b1);
            3'h7: Zero = !(ALUResult == 32'b1);
            end
        endcase
    end
    

endmodule
