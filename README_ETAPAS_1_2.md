# Apresentação das Etapas 1 e 2 - RV32I Pipelined

## 1. Contexto do projeto

Este projeto implementa um processador **RISC-V RV32I** em **SystemVerilog**, usando uma arquitetura com pipeline de 5 estágios:

```text
IF -> ID -> EX -> MEM -> WB
```

No começo, o processador já vinha com um subconjunto pequeno do RV32I:

| Tipo | Instruções que já existiam |
|---|---|
| R-type | `ADD`, `SUB`, `OR`, `AND`, `SLT` |
| I-type load | `LW` |
| S-type | `SW` |
| B-type | `BEQ` |

O objetivo das Etapas 1 e 2 foi aumentar a cobertura do conjunto de instruções RV32I, mantendo a estrutura original do pipeline e mexendo apenas nos arquivos necessários.

---

## 2. Etapa 1 - Aritmética, lógica e deslocamentos

### 2.1 Instruções implementadas

Na Etapa 1 foram implementadas instruções de operações lógicas, aritméticas e deslocamentos.

#### R-type

| Instrução | Função |
|---|---|
| `XOR` | OU exclusivo bit a bit |
| `SLL` | deslocamento lógico para a esquerda |
| `SRL` | deslocamento lógico para a direita |
| `SRA` | deslocamento aritmético para a direita |
| `SLTU` | comparação menor que sem sinal |

#### I-type aritmético

| Instrução | Função |
|---|---|
| `ADDI` | soma com imediato |
| `ANDI` | AND com imediato |
| `ORI` | OR com imediato |
| `SLTI` | comparação menor que com sinal |
| `SLLI` | deslocamento lógico à esquerda com imediato |
| `SRLI` | deslocamento lógico à direita com imediato |
| `SRAI` | deslocamento aritmético à direita com imediato |

### 2.2 O que foi alterado

| Arquivo | Motivo da alteração |
|---|---|
| `pl_alu.sv` | Adicionar as operações novas da ALU: `XOR`, `SLL`, `SRL`, `SRA`, `SLTU` |
| `pl_alu_ctrl.sv` | Decodificar `funct3` e `funct7` das novas instruções R-type e I-type |
| `pl_control.sv` | Reconhecer o opcode `0010011` das instruções I-type aritméticas |
| `pl_sign_ext.sv` | Gerar imediato para as instruções I-type |

### 2.3 Como funciona no pipeline

As instruções da Etapa 1 seguem o fluxo normal:

```text
IF  -> busca da instrução
ID  -> decodificação e leitura dos registradores
EX  -> execução na ALU
MEM -> não acessa memória
WB  -> escreve o resultado no registrador destino
```

Para as instruções R-type, os dois operandos vêm dos registradores. Para as instruções I-type, o segundo operando vem do imediato estendido pelo `pl_sign_ext`.

Exemplo:

```asm
addi x1,x0,5
slli x2,x1,2
xor  x3,x1,x2
```

Nesse caso:

- `ADDI` coloca `5` em `x1`;
- `SLLI` desloca `x1` duas posições para a esquerda;
- `XOR` faz a operação entre dois registradores.

---

## 3. Etapa 2 - Memória, desvios, jumps e U-type

### 3.1 Instruções implementadas

Na Etapa 2 foram implementadas instruções que exigem mudanças maiores no caminho de dados, porque envolvem acesso parcial à memória, alteração do PC e novos tipos de resultado no write-back.

#### Acesso à memória

| Tipo | Instruções |
|---|---|
| Loads | `LB`, `LH`, `LBU`, `LHU` |
| Stores | `SB`, `SH` |

#### Desvios e jumps

| Tipo | Instruções |
|---|---|
| Branch | `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| Jump | `JAL`, `JALR` |

#### Imediato superior

| Tipo | Instruções |
|---|---|
| U-type | `LUI`, `AUIPC` |

---

## 4. Implementação da Etapa 2

### 4.1 Loads menores: `LB`, `LH`, `LBU`, `LHU`

Antes, o processador só carregava uma palavra inteira com `LW`.

Agora, no estágio `MEM`, o processador escolhe qual parte da palavra de 32 bits deve ser carregada:

| Instrução | Resultado |
|---|---|
| `LB` | carrega 1 byte e faz extensão com sinal |
| `LH` | carrega 16 bits e faz extensão com sinal |
| `LBU` | carrega 1 byte e completa com zeros |
| `LHU` | carrega 16 bits e completa com zeros |

Exemplo:

```text
dmem[0] = 0x80FF7F01
```

Em little-endian:

| Endereço | Byte |
|---|---|
| `0` | `0x01` |
| `1` | `0x7F` |
| `2` | `0xFF` |
| `3` | `0x80` |

Então:

```asm
lb  x1,2(x0)   # x1 = 0xFFFFFFFF
lbu x2,2(x0)   # x2 = 0x000000FF
```

A diferença é que `LB` interpreta o byte como valor com sinal, enquanto `LBU` interpreta como valor sem sinal.

### 4.2 Stores menores: `SB`, `SH`

Antes, o processador só escrevia uma palavra inteira com `SW`.

Para implementar `SB` e `SH`, foi adicionado um sinal de **byte enable** na memória de dados:

```text
ByteEn[0] -> byte menos significativo
ByteEn[1] -> segundo byte
ByteEn[2] -> terceiro byte
ByteEn[3] -> byte mais significativo
```

Assim:

| Instrução | Quantidade escrita |
|---|---|
| `SB` | 1 byte |
| `SH` | 2 bytes |
| `SW` | 4 bytes |

Exemplo usado no teste:

```text
dmem[1] inicial = 0x11223344
sb x6,5(x0)     # altera apenas um byte
sh x7,6(x0)     # altera meia palavra
dmem[1] final   = 0xBEEFAA44
```

### 4.3 Branches novos

O `BEQ` já existia. Na Etapa 2 foram adicionados:

| Instrução | Condição |
|---|---|
| `BNE` | diferente |
| `BLT` | menor que com sinal |
| `BGE` | maior ou igual com sinal |
| `BLTU` | menor que sem sinal |
| `BGEU` | maior ou igual sem sinal |

O branch continua sendo resolvido no estágio `EX`. Quando o branch é tomado, o pipeline faz flush das instruções que foram buscadas no caminho errado.

### 4.4 Jumps: `JAL` e `JALR`

As instruções de jump precisaram de dois comportamentos:

1. Alterar o `PC`.
2. Escrever `PC + 4` no registrador destino.

Para isso, foi criado um seletor novo de write-back chamado `ResultSrc`.

| `ResultSrc` | Valor escrito no registrador |
|---|---|
| `00` | resultado da ALU |
| `01` | dado vindo da memória |
| `10` | `PC + 4` |
| `11` | imediato, usado pelo `LUI` |

No caso do `JALR`, o endereço de destino é calculado como:

```text
(rs1 + imediato) & 0xFFFFFFFE
```

Ou seja, o bit menos significativo do endereço é zerado, como definido pelo RISC-V.

### 4.5 U-type: `LUI` e `AUIPC`

As instruções U-type usam um imediato de 20 bits colocado na parte alta da palavra.

| Instrução | Resultado |
|---|---|
| `LUI` | escreve `imediato << 12` no registrador |
| `AUIPC` | escreve `PC + (imediato << 12)` |

Para o `AUIPC`, foi necessário permitir que a entrada A da ALU viesse do `PC`, e não apenas de `rs1`.

---

## 5. Arquivos modificados na Etapa 2

| Arquivo | O que foi feito |
|---|---|
| `pl_control.sv` | Novos opcodes e novos sinais de controle: `Jump`, `JumpReg`, `ALUASrc`, `ResultSrc` |
| `pl_sign_ext.sv` | Imediatos dos tipos `I`, `S`, `B`, `U` e `J` |
| `pl_pipe_pkg.sv` | Novos campos nos registradores de pipeline |
| `pl_cpu.sv` | Conexão dos novos sinais entre controle e datapath |
| `pl_datapath.sv` | Lógica de branch, jump, write-back, loads menores e stores menores |
| `pl_dmem.sv` | Escrita com byte enable para `SB`, `SH` e `SW` |

Não foi necessário alterar `pl_hazard.sv` nem `pl_forward.sv`, porque a lógica já existente continuou suficiente para manter o pipeline correto. Também não foi necessário alterar a ALU para a Etapa 2, pois as operações novas dessa etapa usam comparadores no datapath, soma já existente ou seleção de write-back.

---

## 6. O que foi alterado no código

Esta parte serve como roteiro direto para a apresentação. Em cada item, eu indico o arquivo, as linhas principais alteradas, o que foi feito no código e por que essa alteração foi necessária.

### 6.1 Etapa 1 no código

#### Operações novas na ALU

**Arquivo:** `src/pl_alu.sv`

**Linhas principais:** 32 a 50.

**O que eu alterei:** adicionei os códigos internos da ALU para `XOR`, `SLL`, `SRL`, `SRA` e `SLTU`, e também adicionei os casos que calculam o resultado dessas operações.

**Por que alterei:** essas instruções R-type precisam ser executadas diretamente pela ALU no estágio `EX`. Sem esses casos, o controle até poderia decodificar a instrução, mas a ALU não saberia qual operação realizar.

Trecho principal:

```systemverilog
localparam ALU_XOR  = 4'd06;
localparam ALU_SLL  = 4'd07;
localparam ALU_SRL  = 4'd08;
localparam ALU_SRA  = 4'd09;
localparam ALU_SLTU = 4'd12;

ALU_XOR:  ALUResult = SrcA ^ SrcB;
ALU_SLL:  ALUResult = SrcA << SrcB[4:0];
ALU_SRL:  ALUResult = SrcA >> SrcB[4:0];
ALU_SRA:  ALUResult = $signed(SrcA) >>> SrcB[4:0];
ALU_SLTU: ALUResult = {31'b0, (SrcA < SrcB)};
```

Na apresentação, eu explicaria que o deslocamento usa apenas `SrcB[4:0]` porque, no RV32I, só existem 32 posições possíveis de deslocamento, de 0 a 31.

#### Decodificação das instruções R-type e I-type

**Arquivo:** `src/pl_alu_ctrl.sv`

**Linhas principais:** 45 a 66.

**O que eu alterei:** alterei a lógica de controle da ALU para mapear `funct3` e `funct7` para as novas operações da Etapa 1. No bloco R-type, foram adicionadas as operações `SLL`, `SLTU`, `XOR`, `SRL` e `SRA`. No bloco I-type, foram adicionadas as operações `ADDI`, `SLLI`, `SLTI`, `SRLI`, `SRAI`, `ORI` e `ANDI`.

**Por que alterei:** a ALU recebe apenas um código de operação, então o `pl_alu_ctrl` precisa traduzir os campos da instrução RISC-V para esse código interno da ALU.

Trecho principal:

```systemverilog
2'b10: begin
    case (Funct3)
        3'h1: Operation = ALU_SLL;
        3'h3: Operation = ALU_SLTU;
        3'h4: Operation = ALU_XOR;
        3'h5: Operation = Funct7[5] ? ALU_SRA : ALU_SRL;
    endcase
end

2'b11: begin
    case (Funct3)
        3'h0: Operation = ALU_ADD; // ADDI
        3'h1: Operation = ALU_SLL; // SLLI
        3'h2: Operation = ALU_SLT; // SLTI
        3'h5: Operation = Funct7[5] ? ALU_SRA : ALU_SRL;
        3'h6: Operation = ALU_OR;  // ORI
        3'h7: Operation = ALU_AND; // ANDI
    endcase
end
```

Na apresentação, eu destacaria que `Funct7[5]` é o bit usado para diferenciar `SRL` de `SRA` e também `SRLI` de `SRAI`.

#### Controle principal das instruções I-type

**Arquivo:** `src/pl_control.sv`

**Linhas principais:** 73 a 78.

**O que eu alterei:** adicionei o comportamento do opcode `0010011`, que representa as instruções I-type aritméticas.

**Por que alterei:** essas instruções usam imediato como segundo operando e escrevem o resultado no registrador destino. Por isso, o controle precisa ativar `ALUSrc`, `RegWrite` e selecionar `ALUOp = 2'b11`.

Trecho principal:

```systemverilog
I_TYPE: begin
    ALUSrc   = 1'b1;
    MemtoReg = 1'b0;
    RegWrite = 1'b1;
    ALUOp    = 2'b11;
end
```

Na apresentação, eu explicaria que `ALUSrc = 1` faz a ALU usar o imediato, e `ALUOp = 2'b11` avisa ao `pl_alu_ctrl` que ele deve decodificar uma instrução I-type aritmética.

#### Imediato das instruções I-type

**Arquivo:** `src/pl_sign_ext.sv`

**Linhas principais:** 33 a 35.

**O que eu alterei:** incluí o formato I-type na extensão de imediato, usando os bits `Instr[31:20]`.

**Por que alterei:** as instruções como `ADDI`, `ANDI`, `ORI`, `SLTI`, `SLLI`, `SRLI` e `SRAI` precisam que o imediato seja levado para 32 bits antes de entrar na ALU.

Trecho principal:

```systemverilog
I_TYPE,
JALR,
LOAD: ImmExt = {{20{Instr[31]}}, Instr[31:20]};
```

Na apresentação, eu explicaria que o imediato de 12 bits vira um valor de 32 bits para poder ser usado junto com os registradores, que também têm 32 bits.

### 6.2 Etapa 2 no código

#### Novos sinais de controle

**Arquivo:** `src/pl_control.sv`

**Linhas principais:** 45 a 51 e 79 a 118.

**O que eu alterei:** adicionei os opcodes da Etapa 2 (`LOAD`, `STORE`, `BRANCH`, `JAL`, `JALR`, `LUI`, `AUIPC`) e criei os sinais de controle necessários para jumps, U-type e novos caminhos de write-back.

**Por que alterei:** o controle principal é quem identifica o tipo da instrução no estágio `ID`. Sem esses opcodes e sinais, o datapath não saberia quando mudar o `PC`, quando escrever `PC+4`, quando usar o `PC` como entrada da ALU ou quando escrever um imediato no registrador.

Trecho dos opcodes:

```systemverilog
localparam LOAD   = 7'b0000011;
localparam STORE  = 7'b0100011;
localparam BRANCH = 7'b1100011;
localparam JAL    = 7'b1101111;
localparam JALR   = 7'b1100111;
localparam LUI    = 7'b0110111;
localparam AUIPC  = 7'b0010111;
```

Trecho importante do controle de `JAL`, `JALR`, `LUI` e `AUIPC`:

```systemverilog
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
```

Na apresentação, eu explicaria que `ResultSrc` foi necessário porque o valor escrito no registrador agora pode vir da ALU, da memória, do `PC+4` ou do imediato.

#### Imediatos dos tipos S, B, U e J

**Arquivo:** `src/pl_sign_ext.sv`

**Linhas principais:** 37 a 46.

**O que eu alterei:** adicionei a montagem dos imediatos dos formatos `S`, `B`, `U` e `J`.

**Por que alterei:** a Etapa 2 usa instruções de store, branch, jump e U-type. Cada uma dessas instruções guarda o imediato em posições diferentes dentro dos 32 bits da instrução. Então o `sign_ext` precisa reorganizar esses bits no formato correto.

Trecho principal:

```systemverilog
STORE:  ImmExt = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};

BRANCH: ImmExt = {{19{Instr[31]}}, Instr[31], Instr[7],
                   Instr[30:25], Instr[11:8], 1'b0};

JAL:    ImmExt = {{11{Instr[31]}}, Instr[31], Instr[19:12],
                   Instr[20], Instr[30:21], 1'b0};

LUI,
AUIPC:  ImmExt = {Instr[31:12], 12'b0};
```

Na apresentação, eu explicaria que os formatos `B` e `J` já colocam o bit zero como `0`, porque os desvios em RISC-V são alinhados.

#### Novos campos nos registradores de pipeline

**Arquivo:** `src/pl_pipe_pkg.sv`

**Linhas principais:** 29 a 36, 47 a 61 e 64 a 75.

**O que eu alterei:** adicionei novos campos nos registradores de pipeline, como `jump`, `jump_reg`, `alu_a_src`, `result_src` e `pc_plus4`.

**Por que alterei:** em um processador pipelined, os sinais gerados no decode precisam acompanhar a instrução pelos estágios seguintes. Por exemplo, `JAL` descobre no decode que precisa escrever `PC+4`, mas esse valor só é escrito no estágio `WB`.

Trecho principal:

```systemverilog
logic        jump;
logic        jump_reg;
logic        alu_a_src;
logic [1:0]  result_src;
logic [31:0] pc_plus4;
```

Na apresentação, eu explicaria que isso é uma consequência direta do pipeline: uma informação decidida no estágio `ID` precisa chegar corretamente até `EX`, `MEM` ou `WB`.

#### Conexão entre controle e datapath

**Arquivo:** `src/pl_cpu.sv`

**Linhas principais:** 48 a 102.

**O que eu alterei:** declarei os sinais novos (`Jump`, `JumpReg`, `ALUASrc`, `ResultSrc`) e conectei esses sinais entre o `pl_control` e o `pl_datapath`.

**Por que alterei:** o `pl_cpu` é o wrapper que liga a unidade de controle ao datapath. Como a Etapa 2 criou novos sinais de controle, eles precisavam passar por esse arquivo.

Trecho principal:

```systemverilog
logic       Jump, JumpReg, ALUASrc;
logic [1:0] ResultSrc;

.Jump      (Jump),
.JumpReg   (JumpReg),
.ALUASrc   (ALUASrc),
.ResultSrc (ResultSrc),
```

Na apresentação, eu explicaria que essa alteração não muda a lógica do processador sozinha, mas é necessária para que os novos sinais cheguem ao datapath.

#### Mux de write-back com `ResultSrc`

**Arquivo:** `src/pl_datapath.sv`

**Linhas principais:** 162 a 169.

**O que eu alterei:** substituí a escolha simples do write-back por uma seleção baseada em `result_src`.

**Por que alterei:** antes, o processador precisava basicamente escolher entre resultado da ALU e dado vindo da memória. Com `JAL`, `JALR` e `LUI`, também é necessário escrever `PC+4` e imediato no registrador destino.

Trecho principal:

```systemverilog
case (mem_wb.result_src)
    2'b01:   wb_data = mem_wb.read_data;   // loads
    2'b10:   wb_data = mem_wb.pc_plus4;    // jal / jalr
    2'b11:   wb_data = mem_wb.imm_ext;     // lui
    default: wb_data = mem_wb.alu_result;  // ALU / auipc
endcase
```

Na apresentação, eu destacaria que esse mux é uma das mudanças centrais da Etapa 2, porque ele permite mais fontes de escrita no banco de registradores.

#### Branches e jumps

**Arquivo:** `src/pl_datapath.sv`

**Linhas principais:** 324 a 339.

**O que eu alterei:** implementei a comparação dos novos branches (`BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`) e a escolha do próximo `PC` para branch, `JAL` e `JALR`.

**Por que alterei:** o `BEQ` antigo só testava igualdade. A Etapa 2 exige comparações com sinal, sem sinal e jumps. Além disso, `JALR` precisa calcular o destino com `rs1 + imediato` e zerar o bit menos significativo.

Trecho principal:

```systemverilog
case (id_ex.funct3)
    3'b000:  branch_taken = (fwd_srca == fwd_srcb);                  // BEQ
    3'b001:  branch_taken = (fwd_srca != fwd_srcb);                  // BNE
    3'b100:  branch_taken = ($signed(fwd_srca) <  $signed(fwd_srcb)); // BLT
    3'b101:  branch_taken = ($signed(fwd_srca) >= $signed(fwd_srcb)); // BGE
    3'b110:  branch_taken = (fwd_srca <  fwd_srcb);                  // BLTU
    3'b111:  branch_taken = (fwd_srca >= fwd_srcb);                  // BGEU
endcase

assign pc_target = id_ex.jump_reg ? {alu_result[31:1], 1'b0}
                                  : (id_ex.pc + id_ex.imm_ext);
assign pc_src    = (id_ex.branch && branch_taken) || id_ex.jump;
```

Na apresentação, eu explicaria que os branches com sinal usam `$signed`, e os branches sem sinal usam comparação normal. Também mostraria que o `JALR` usa `{alu_result[31:1], 1'b0}` para forçar o endereço a ser alinhado.

#### Stores menores com byte enable

**Arquivos:** `src/pl_datapath.sv` e `src/pl_dmem.sv`

**Linhas principais:** `pl_datapath.sv`, linhas 377 a 409, e `pl_dmem.sv`, linhas 16 a 43.

**O que eu alterei:** no datapath, adicionei a lógica que calcula quais bytes devem ser escritos para `SB`, `SH` e `SW`. Na memória de dados, adicionei a entrada `ByteEn` e alterei a escrita para atualizar apenas os bytes selecionados.

**Por que alterei:** `SW` escreve 32 bits, mas `SB` escreve só 8 bits e `SH` escreve só 16 bits. Sem `ByteEn`, qualquer store sobrescreveria a palavra inteira.

Trecho principal no datapath:

```systemverilog
case (ex_mem.funct3)
    3'b000: begin // SB
        store_write_data = {4{ex_mem.write_data[7:0]}};
        case (ex_mem.alu_result[1:0])
            2'b00:   store_byte_en = 4'b0001;
            2'b01:   store_byte_en = 4'b0010;
            2'b10:   store_byte_en = 4'b0100;
            default: store_byte_en = 4'b1000;
        endcase
    end
    3'b001: begin // SH
        store_write_data = {2{ex_mem.write_data[15:0]}};
        store_byte_en    = ex_mem.alu_result[1] ? 4'b1100 : 4'b0011;
    end
endcase
```

Trecho principal na memória:

```systemverilog
if (ByteEn[0]) ram[addr][7:0]   <= WriteData[7:0];
if (ByteEn[1]) ram[addr][15:8]  <= WriteData[15:8];
if (ByteEn[2]) ram[addr][23:16] <= WriteData[23:16];
if (ByteEn[3]) ram[addr][31:24] <= WriteData[31:24];
```

Na apresentação, eu explicaria que `ByteEn` funciona como uma máscara de escrita: cada bit habilita um byte da palavra de 32 bits.

#### Loads menores com extensão correta

**Arquivo:** `src/pl_datapath.sv`

**Linhas principais:** 429 a 446.

**O que eu alterei:** adicionei a seleção do byte ou halfword dentro da palavra lida da memória e implementei a extensão correta para `LB`, `LH`, `LBU` e `LHU`.

**Por que alterei:** `LW` sempre carrega 32 bits, mas as novas instruções carregam apenas parte da palavra. Além disso, `LB` e `LH` precisam extensão com sinal, enquanto `LBU` e `LHU` precisam extensão com zero.

Trecho principal:

```systemverilog
case (ex_mem.funct3)
    3'b000:  load_data = {{24{load_byte[7]}}, load_byte}; // LB
    3'b001:  load_data = {{16{load_half[15]}}, load_half}; // LH
    3'b100:  load_data = {24'b0, load_byte};               // LBU
    3'b101:  load_data = {16'b0, load_half};               // LHU
    default: load_data = mem_read_data;                    // LW
endcase
```

Na apresentação, eu explicaria a diferença entre instruções com sinal e sem sinal usando o exemplo de `0xFF`: em `LB`, vira `0xFFFFFFFF`; em `LBU`, vira `0x000000FF`.

### 6.3 Código do testbench

**Arquivo criado:** `src/pl_cpu_stage2_tb.sv`

**Linhas principais:** 228 a 285 para montar o programa de teste, e 327 a 347 para conferir os resultados.

**O que eu fiz:** criei um testbench específico para a Etapa 2. Em vez de depender de um arquivo `.asm`, o próprio testbench monta as instruções, escreve diretamente na memória de instruções e inicializa a memória de dados com valores conhecidos.

**Por que fiz assim:** desse jeito o teste fica independente dos arquivos `program.hex`, `data.hex`, `instruction.mif` e `data.mif`. Isso facilita testar só a lógica da Etapa 2 no simulador.

Trecho do programa de teste:

```systemverilog
emit(enc_i(2, 5'd0, F3_LB,  5'd1, OP_LOAD), "lb   x1,2(x0)");
emit(enc_i(2, 5'd0, F3_LH,  5'd2, OP_LOAD), "lh   x2,2(x0)");
emit(enc_s(5, 5'd6, 5'd0, F3_SB),            "sb   x6,5(x0)");
emit(enc_s(6, 5'd7, 5'd0, F3_SH),            "sh   x7,6(x0)");
emit(enc_j(8, 5'd22),                        "jal  x22,+8");
emit(enc_i(0, 5'd23, F3_ADDI, 5'd24, OP_JALR), "jalr x24,x23,0");
```

Trecho das checagens finais:

```systemverilog
check_reg(1, 32'hFFFFFFFF, "LB com sinal");
check_reg(3, 32'h000000FF, "LBU sem sinal");
check_mem(1, 32'hBEEFAA44, "SB + SH");
check_reg(20, 32'h12345000, "LUI");
check_reg(22, (jal_word * 4) + 4, "JAL link PC+4");
check_reg(24, (jalr_word * 4) + 4, "JALR link PC+4");
```

Na apresentação, eu explicaria que o testbench testa tanto o caminho correto quanto possíveis erros. Por exemplo, `x31` deve terminar zerado porque os branches e jumps tomados pulam instruções que somariam valores nele.

---

## 7. Testes

### 7.1 Testbench da Etapa 2

Foi criado o arquivo:

```text
src/pl_cpu_stage2_tb.sv
```

Esse testbench carrega um programa direto na memória de instruções do processador e inicializa a memória de dados com valores controlados.

Ele verifica:

| Grupo | O que o teste confere |
|---|---|
| Loads | extensão com sinal e extensão com zero |
| Stores | escrita parcial em byte e halfword |
| Branches | casos tomados e não tomados |
| Jumps | desvio correto e escrita de `PC + 4` |
| U-type | resultado correto de `LUI` e `AUIPC` |

No fim da simulação, a mensagem esperada é:

```text
PASS: Etapa 2 funcionando.
```

### 7.2 Exemplo de resultados esperados

Alguns valores verificados pelo testbench:

| Registrador/memória | Valor esperado | Motivo |
|---|---:|---|
| `x1` | `0xFFFFFFFF` | `LB` com byte `0xFF` |
| `x3` | `0x000000FF` | `LBU` com byte `0xFF` |
| `x4` | `0x000080FF` | `LHU` |
| `dmem[1]` | `0xBEEFAA44` | resultado de `SB` e `SH` |
| `x20` | `0x12345000` | resultado de `LUI` |
| `x30` | `0x00000005` | branches falsos não foram tomados |
| `x31` | `0x00000000` | branches e jumps tomados pularam os erros |

---

## 8. Cobertura após as Etapas 1 e 2

Considerando o subconjunto inicial mais as Etapas 1 e 2:

| Categoria | Implementadas |
|---|---|
| R-type | `ADD`, `SUB`, `OR`, `AND`, `SLT`, `XOR`, `SLL`, `SRL`, `SRA`, `SLTU` |
| I-type aritmético | `ADDI`, `ANDI`, `ORI`, `SLTI`, `SLLI`, `SRLI`, `SRAI` |
| I-type load | `LW`, `LB`, `LH`, `LBU`, `LHU` |
| S-type | `SW`, `SB`, `SH` |
| B-type | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| U-type | `LUI`, `AUIPC` |
| J-type | `JAL`, `JALR` |

Das 37 instruções consideradas na tabela do projeto, ficam implementadas 35. As duas instruções I-type aritméticas que ainda não foram pedidas são:

```text
XORI
SLTIU
```

---

## 9. Roteiro curto para apresentar

Uma forma simples de apresentar seria:

1. Primeiro, explicar que o processador original já tinha pipeline de 5 estágios e suportava só 8 instruções.
2. Na Etapa 1, mostrar que foram adicionadas operações de ALU e imediatos, principalmente mexendo no controle da ALU, na ALU, no controle principal e no extensor de imediato.
3. Na Etapa 2, explicar que a mudança foi maior porque entraram instruções que alteram memória parcialmente, mudam o PC e escrevem valores diferentes no write-back.
4. Mostrar o papel do `ResultSrc`, porque ele permite escolher entre ALU, memória, `PC+4` e imediato.
5. Mostrar o `ByteEn`, porque ele permite que `SB` e `SH` escrevam só parte da palavra.
6. Encerrar mostrando o testbench da Etapa 2 e a mensagem `PASS`.

---

## 10. Conclusão

As Etapas 1 e 2 aumentaram bastante a cobertura do processador RV32I. A Etapa 1 expandiu a ALU e as instruções com imediato. A Etapa 2 adicionou acesso parcial à memória, novos desvios condicionais, jumps e instruções U-type.

O ponto principal da implementação foi manter o pipeline original e acrescentar apenas os sinais necessários para transportar os novos dados entre os estágios. Com isso, o processador continuou seguindo a organização base do projeto, mas passou a executar quase todo o conjunto RV32I listado no trabalho.
