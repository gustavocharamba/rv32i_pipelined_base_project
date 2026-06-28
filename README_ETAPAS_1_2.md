# Apresentação das Etapas 1 e 2 — RV32I Pipelined

## 1. Objetivo

Neste trabalho, parti de um processador RV32I com pipeline de cinco estágios:

```text
IF -> ID -> EX -> MEM -> WB
```

O objetivo foi implementar somente as instruções solicitadas nas Etapas 1 e 2, mantendo a organização original do processador e acrescentando ao caminho de dados e ao controle apenas o que era necessário para executá-las.

---

## 2. Etapa 1 — Aritmética, lógica e deslocamentos

Na primeira etapa, implementei novas operações entre registradores e novas operações com valores imediatos.

### 2.1 Instruções R-type

As instruções solicitadas foram:

| Instrução | Operação |
|---|---|
| `XOR` | OU exclusivo bit a bit |
| `SLL` | deslocamento lógico para a esquerda |
| `SRL` | deslocamento lógico para a direita |
| `SRA` | deslocamento aritmético para a direita |
| `SLTU` | comparação “menor que” sem sinal |

Para implementar essas instruções, acrescentei as novas operações à ALU e atualizei o controle da ALU para interpretar os campos `funct3` e `funct7`.

O campo `funct7` permite diferenciar operações que compartilham o mesmo `funct3`, como `SRL` e `SRA`. Nos deslocamentos, a ALU utiliza somente os cinco bits menos significativos do segundo operando, permitindo deslocamentos de 0 a 31 posições.

### 2.2 Instruções I-type

As instruções com imediato solicitadas foram:

| Instrução | Operação |
|---|---|
| `ADDI` | soma com imediato |
| `ANDI` | AND com imediato |
| `ORI` | OR com imediato |
| `SLTI` | comparação “menor que” com sinal |
| `SLLI` | deslocamento lógico para a esquerda |
| `SRLI` | deslocamento lógico para a direita |
| `SRAI` | deslocamento aritmético para a direita |

Para reconhecer esse grupo, adicionei ao controle principal o opcode das instruções aritméticas I-type. Nesse caso, o segundo operando da ALU vem do imediato da instrução, em vez de vir do segundo registrador.

Também atualizei o extensor de imediato para obter o valor presente em `Instr[31:20]` e disponibilizá-lo com 32 bits no estágio de execução.

### 2.3 Funcionamento no pipeline

As instruções da Etapa 1 percorrem o pipeline normalmente:

```text
IF  -> busca da instrução
ID  -> decodificação, leitura dos registradores e geração do imediato
EX  -> execução da operação na ALU
MEM -> passagem do resultado, sem acesso à memória
WB  -> escrita do resultado em rd
```

---

## 3. Etapa 2 — Memória, desvios, jumps e U-type

Na segunda etapa, implementei as instruções solicitadas de acesso parcial à memória, desvios condicionais, jumps e imediato superior.

### 3.1 Loads

As novas instruções de leitura da memória foram:

| Instrução | Valor carregado |
|---|---|
| `LB` | byte com extensão de sinal |
| `LH` | halfword com extensão de sinal |
| `LBU` | byte com extensão de zero |
| `LHU` | halfword com extensão de zero |

No estágio `MEM`, utilizo os bits menos significativos do endereço para selecionar o byte ou o halfword dentro da palavra de 32 bits lida da memória.

Depois da seleção:

- `LB` e `LH` repetem o bit de sinal até completar 32 bits;
- `LBU` e `LHU` completam o resultado com zeros.

Por exemplo, ao carregar o byte `0xFF`, o resultado de `LB` é `0xFFFFFFFF`, enquanto o resultado de `LBU` é `0x000000FF`.

### 3.2 Stores

As novas instruções de escrita foram:

| Instrução | Quantidade escrita |
|---|---|
| `SB` | um byte |
| `SH` | dois bytes |

Implementei essas instruções no estágio `MEM` por meio da composição da palavra que será gravada.

Primeiro, o datapath lê a palavra existente na memória. Em seguida, substitui somente o byte indicado por `SB` ou o halfword indicado por `SH`. Por fim, grava novamente a palavra de 32 bits já combinada. Dessa forma, os bytes que não fazem parte da operação são preservados.

### 3.3 Desvios condicionais

Os novos branches solicitados foram:

| Instrução | Condição |
|---|---|
| `BNE` | diferente |
| `BLT` | menor que, com sinal |
| `BGE` | maior ou igual, com sinal |
| `BLTU` | menor que, sem sinal |
| `BGEU` | maior ou igual, sem sinal |

As comparações são realizadas no estágio `EX`. Para `BLT` e `BGE`, trato os operandos como valores com sinal. Para `BLTU` e `BGEU`, a comparação é feita sem sinal.

Quando a condição é verdadeira, o próximo PC recebe `PC + imediato`. Como a decisão acontece em `EX`, as instruções que já entraram no pipeline pelo caminho incorreto são descartadas.

### 3.4 Jumps

As instruções de jump solicitadas foram:

| Instrução | Destino |
|---|---|
| `JAL` | `PC + imediato` |
| `JALR` | `(rs1 + imediato) & 0xFFFFFFFE` |

As duas instruções também escrevem `PC + 4` no registrador de destino, permitindo o retorno ao ponto seguinte do programa.

Para transportar esse valor até o estágio `WB`, acrescentei `pc_plus4` aos registradores do pipeline. No caso de `JALR`, o bit menos significativo do endereço calculado é zerado.

### 3.5 Instruções U-type

As instruções solicitadas foram:

| Instrução | Resultado escrito em `rd` |
|---|---|
| `LUI` | `imediato << 12` |
| `AUIPC` | `PC + (imediato << 12)` |

O extensor de imediato monta o valor U-type colocando os 20 bits da instrução na parte superior da palavra.

Para `LUI`, esse imediato segue diretamente para o write-back. Para `AUIPC`, alterei a seleção da primeira entrada da ALU para que ela possa receber o PC e somá-lo ao imediato.

---

## 4. Implementação no código

Nesta parte, apresento os principais trechos que alterei para implementar as instruções solicitadas.

### 4.1 Novas operações da ALU

**Arquivo:** `src/pl_alu.sv`

Na Etapa 1, acrescentei à ALU as operações de XOR, deslocamento e comparação sem sinal:

```systemverilog
ALU_XOR:  ALUResult = SrcA ^ SrcB;
ALU_SLL:  ALUResult = SrcA << SrcB[4:0];
ALU_SRL:  ALUResult = SrcA >> SrcB[4:0];
ALU_SRA:  ALUResult = $signed(SrcA) >>> SrcB[4:0];
ALU_SLTU: ALUResult = {31'b0, (SrcA < SrcB)};
```

O `SRA` utiliza `$signed` para preservar o sinal durante o deslocamento. O `SLTU` faz a comparação diretamente como valor sem sinal e produz `0` ou `1`.

### 4.2 Controle da ALU

**Arquivo:** `src/pl_alu_ctrl.sv`

Atualizei a decodificação de `funct3` e `funct7` para selecionar as operações R-type e I-type da Etapa 1:

```systemverilog
2'b10: begin // R-type
    case (Funct3)
        3'h1: Operation = ALU_SLL;
        3'h3: Operation = ALU_SLTU;
        3'h4: Operation = ALU_XOR;
        3'h5: Operation = Funct7[5] ? ALU_SRA : ALU_SRL;
        // Os casos de ADD, SUB, SLT, OR e AND foram mantidos.
        default: Operation = ALU_ADD;
    endcase
end

2'b11: begin // I-type aritmético
    case (Funct3)
        3'h0: Operation = ALU_ADD; // ADDI
        3'h1: Operation = ALU_SLL; // SLLI
        3'h2: Operation = ALU_SLT; // SLTI
        3'h5: Operation = Funct7[5] ? ALU_SRA : ALU_SRL;
        3'h6: Operation = ALU_OR;  // ORI
        3'h7: Operation = ALU_AND; // ANDI
        default: Operation = ALU_ADD;
    endcase
end
```

O sinal `ALUOp` identifica o grupo da instrução. Depois disso, o controle usa os campos de função para escolher a operação específica.

### 4.3 Controle principal e write-back

**Arquivos:** `src/pl_control.sv` e `src/pl_datapath.sv`

Para as instruções I-type da Etapa 1, configurei o controle para usar o imediato como segundo operando e escrever o resultado da ALU no registrador:

```systemverilog
I_TYPE: begin
    ALUSrc   = 1'b1;
    MemtoReg = 1'b0;
    RegWrite = 1'b1;
    ALUOp    = 2'b11;
end
```

Para os jumps e as instruções U-type, adicionei os sinais que selecionam o próximo PC, o valor de retorno e as entradas da ALU:

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
    ALUSrc   = 1'b1;
    ALUASrc  = 1'b1;
    RegWrite = 1'b1;
    ALUOp    = 2'b00;
end
```

Como as instruções passaram a ter novas possíveis fontes de resultado, implementei no datapath o seletor `ResultSrc`:

```systemverilog
case (mem_wb.result_src)
    2'b01:   wb_data = mem_wb.read_data;   // loads
    2'b10:   wb_data = mem_wb.pc_plus4;    // JAL e JALR
    2'b11:   wb_data = mem_wb.imm_ext;     // LUI
    default: wb_data = mem_wb.alu_result;  // ALU e AUIPC
endcase
```

Com esse multiplexador, o mesmo estágio de write-back atende aos resultados da ALU, aos loads, aos jumps e ao `LUI`.

### 4.4 Geração dos imediatos

**Arquivo:** `src/pl_sign_ext.sv`

O extensor reorganiza os campos da instrução de acordo com o formato utilizado:

```systemverilog
I_TYPE,
JALR,
LOAD:   ImmExt = {{20{Instr[31]}}, Instr[31:20]};

STORE:  ImmExt = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};

BRANCH: ImmExt = {{19{Instr[31]}}, Instr[31], Instr[7],
                   Instr[30:25], Instr[11:8], 1'b0};

JAL:    ImmExt = {{11{Instr[31]}}, Instr[31], Instr[19:12],
                   Instr[20], Instr[30:21], 1'b0};

LUI,
AUIPC:  ImmExt = {Instr[31:12], 12'b0};
```

Esse bloco fornece à ALU e à lógica de atualização do PC o imediato de 32 bits já montado no formato correto.

### 4.5 Branches e jumps

**Arquivo:** `src/pl_datapath.sv`

Implementei as condições dos branches usando comparação com sinal ou sem sinal, conforme a instrução:

```systemverilog
case (id_ex.funct3)
    3'b000: branch_taken = (fwd_srca == fwd_srcb);                    // BEQ
    3'b001: branch_taken = (fwd_srca != fwd_srcb);                    // BNE
    3'b100: branch_taken = ($signed(fwd_srca) <  $signed(fwd_srcb)); // BLT
    3'b101: branch_taken = ($signed(fwd_srca) >= $signed(fwd_srcb)); // BGE
    3'b110: branch_taken = (fwd_srca <  fwd_srcb);                    // BLTU
    3'b111: branch_taken = (fwd_srca >= fwd_srcb);                    // BGEU
    default: branch_taken = 1'b0;
endcase
```

Também defini a escolha do destino para branches, `JAL` e `JALR`:

```systemverilog
assign pc_target = id_ex.jump_reg ? {alu_result[31:1], 1'b0}
                                  : (id_ex.pc + id_ex.imm_ext);

assign pc_src = (id_ex.branch && branch_taken) || id_ex.jump;
```

Quando `jump_reg` está ativo, o destino vem da soma realizada pela ALU para o `JALR`. Nos demais casos, o destino é calculado em relação ao PC da instrução.

### 4.6 Stores parciais

**Arquivo:** `src/pl_datapath.sv`

Para `SB` e `SH`, preservei a parte da palavra que não deve ser modificada e substituí apenas o campo selecionado:

```systemverilog
case (ex_mem.funct3)
    3'b000: begin // SB
        case (ex_mem.alu_result[1:0])
            2'b00: store_write_data =
                {dmem_rd[31:8], ex_mem.write_data[7:0]};
            2'b01: store_write_data =
                {dmem_rd[31:16], ex_mem.write_data[7:0], dmem_rd[7:0]};
            2'b10: store_write_data =
                {dmem_rd[31:24], ex_mem.write_data[7:0], dmem_rd[15:0]};
            default: store_write_data =
                {ex_mem.write_data[7:0], dmem_rd[23:0]};
        endcase
    end

    3'b001: begin // SH
        store_write_data = ex_mem.alu_result[1]
                         ? {ex_mem.write_data[15:0], dmem_rd[15:0]}
                         : {dmem_rd[31:16], ex_mem.write_data[15:0]};
    end

    default: store_write_data = ex_mem.write_data;
endcase
```

Os bits menos significativos do endereço indicam a posição do byte ou do halfword dentro da palavra.

### 4.7 Loads parciais

**Arquivo:** `src/pl_datapath.sv`

Depois de selecionar o byte ou o halfword indicado pelo endereço, aplico a extensão correspondente ao `funct3`:

```systemverilog
case (ex_mem.funct3)
    3'b000: load_data = {{24{load_byte[7]}}, load_byte}; // LB
    3'b001: load_data = {{16{load_half[15]}}, load_half}; // LH
    3'b100: load_data = {24'b0, load_byte};               // LBU
    3'b101: load_data = {16'b0, load_half};               // LHU
    default: load_data = mem_read_data;
endcase
```

Assim, o valor chega ao estágio `WB` já convertido para 32 bits com a extensão correta.

---

## 5. Integração das novas instruções

Para integrar as instruções da Etapa 2, acrescentei os sinais de controle:

| Sinal | Finalidade |
|---|---|
| `Jump` | indica a execução de um jump |
| `JumpReg` | seleciona o destino calculado por `JALR` |
| `ALUASrc` | permite usar o PC como primeira entrada da ALU |
| `ResultSrc` | seleciona a origem do valor escrito em `rd` |

O seletor `ResultSrc` permite escolher entre:

| `ResultSrc` | Origem do write-back |
|---|---|
| `00` | resultado da ALU |
| `01` | dado carregado da memória |
| `10` | `PC + 4` |
| `11` | imediato do `LUI` |

Esses sinais e os dados correspondentes são transportados pelos registradores `ID/EX`, `EX/MEM` e `MEM/WB`, acompanhando cada instrução até o estágio em que são utilizados.

---

## 6. Arquivos envolvidos

### Etapa 1

| Arquivo | Alteração realizada |
|---|---|
| `src/pl_alu.sv` | novas operações aritméticas, lógicas e de deslocamento |
| `src/pl_alu_ctrl.sv` | decodificação de `funct3` e `funct7` |
| `src/pl_control.sv` | controle das instruções I-type aritméticas |
| `src/pl_sign_ext.sv` | geração do imediato I-type |

### Etapa 2

| Arquivo | Alteração realizada |
|---|---|
| `src/pl_control.sv` | controle de jumps, U-type e novas fontes de write-back |
| `src/pl_sign_ext.sv` | montagem dos imediatos utilizados pelas novas instruções |
| `src/pl_pipe_pkg.sv` | novos sinais e dados nos registradores de pipeline |
| `src/pl_cpu.sv` | conexão dos novos sinais entre controle e datapath |
| `src/pl_datapath.sv` | loads e stores parciais, branches, jumps e write-back |
| `src/pl_cpu_stage2_tb.sv` | testbench das instruções solicitadas na Etapa 2 |

---

## 7. Verificação da Etapa 2

O testbench `src/pl_cpu_stage2_tb.sv` monta um programa diretamente na memória de instruções e inicializa a memória de dados com valores conhecidos.

Ele verifica:

- extensão de sinal e de zero nos loads;
- preservação dos outros bytes em `SB` e `SH`;
- branches tomados e não tomados;
- destino e valor de retorno de `JAL` e `JALR`;
- resultados produzidos por `LUI` e `AUIPC`.

As checagens são feitas automaticamente comparando o conteúdo final dos registradores e da memória com os valores esperados.

---

## 8. Conclusão

Na Etapa 1, ampliei as operações executadas pela ALU e adicionei o suporte às instruções aritméticas com imediato solicitadas.

Na Etapa 2, ampliei o caminho de dados para executar acessos parciais à memória, novos desvios condicionais, jumps e instruções U-type. Para isso, adicionei as comparações de branch, os novos caminhos do PC, o transporte de `PC + 4` e a seleção das diferentes fontes de write-back.

Com essas alterações, o processador passou a executar todas as instruções pedidas nas duas etapas sem modificar a organização de cinco estágios do pipeline.
