# Análise de viabilidade do ContextCard no Windows 11

**Data da análise:** 16 de setembro de 2026  
**Escopo:** avaliar a possibilidade de disponibilizar o ContextCard para Windows 11, inventariar as funcionalidades atuais e identificar tecnologias, dependências e riscos para uma futura implementação.

## 1. Conclusão executiva

É plenamente viável criar uma versão Windows 11 com praticamente todas as funcionalidades atuais.

O bloqueio não é a linguagem Swift isoladamente. O aplicativo atual depende de frameworks exclusivos do ecossistema Apple, como `AppKit`, `SwiftUI`, `Vision`, `AVFoundation` e `Speech`. O núcleo lógico, por outro lado, usa HTTP, JSON, geração de HTML, arquivos locais e a API HTTP do AnkiConnect — componentes que podem ser reimplementados em C#.

### Recomendação tecnológica

- **Linguagem:** C#
- **Runtime:** .NET 10 LTS
- **Interface inicial:** WPF
- **APIs nativas:** Windows OCR, Windows Speech Recognition/Synthesis, clipboard e áudio
- **Integração com o Anki:** AnkiConnect via HTTP em `127.0.0.1:8765`
- **Distribuição inicial:** aplicativo autocontido para `win-x64`, com instalador simples

A Microsoft recomenda WinUI 3 para novos aplicativos nativos, mas WPF é uma escolha pragmática para este projeto porque o produto é principalmente um utilitário de bandeja do sistema, com necessidades importantes de clipboard, diálogos, teclado e janelas flutuantes. O Windows App SDK pode ser adotado posteriormente.

## 2. Inventário do aplicativo atual

### 2.1 Aplicativo residente na barra de menu

Arquivo principal: [ContextCardApp.swift](Sources/ContextCard/ContextCardApp.swift)

- Executa como aplicativo residente na barra de menu do macOS.
- Exibe um painel flutuante.
- Fecha ao clicar fora.
- Fecha com `Escape`.
- Possui acesso às configurações.
- Possui comando para sair.
- Implementa navegação customizada com `Tab`, `Shift+Tab` e `Enter`.
- Possui um mecanismo interno para solicitar sincronização da fila por notificação Darwin.

No Windows, esse fluxo seria implementado com um ícone na system tray, uma janela WPF sem moldura ou um pop-up associado ao ícone e um mecanismo de abertura/fechamento equivalente.

### 2.2 Entrada de frase

Arquivos principais: [ClipboardTextEditor.swift](Sources/ContextCard/ClipboardTextEditor.swift) e [Views.swift](Sources/ContextCard/Views.swift)

- Digitação manual de frase em inglês.
- Colagem de texto.
- Editor multiline.
- Controle de foco.
- Atalhos de teclado.
- Colagem especial de imagem no editor.
- Importação de imagem por arquivo.

### 2.3 OCR de imagem

Arquivo principal: [ImageOCRService.swift](Sources/ContextCard/ImageOCRService.swift)

O aplicativo atual:

- aceita uma imagem importada por arquivo;
- aceita uma imagem copiada de outro aplicativo;
- executa OCR local usando o framework Vision;
- tenta reconhecimento rápido;
- usa reconhecimento preciso como fallback;
- restringe o idioma a inglês americano;
- junta as linhas reconhecidas;
- coloca o texto obtido no campo de frase.

No Windows 11, a alternativa nativa é `Windows.Media.Ocr.OcrEngine`. Como fallback, podem ser considerados Tesseract ou OCR remoto.

### 2.4 Gravação de voz e transcrição

Arquivo principal: [VoiceTranscriptionService.swift](Sources/ContextCard/VoiceTranscriptionService.swift)

- Solicita permissão para microfone.
- Inicia gravação pelo botão.
- Reconhece inglês americano.
- Exibe resultados parciais.
- Para a gravação.
- Usa automaticamente o texto final como frase.

O áudio da voz do usuário não é salvo. A gravação serve somente como entrada para produzir texto.

No Windows, há duas possibilidades:

1. Usar `Windows.Media.SpeechRecognition`, com reconhecimento local e resultados parciais.
2. Gravar um arquivo WAV temporário e enviá-lo para uma API de transcrição, como `/v1/audio/transcriptions` da OpenAI.

A segunda opção tende a ser mais consistente entre computadores, mas requer internet e gera custo de API.

### 2.5 Seleção da palavra-chave

Arquivo principal: [TextProcessing.swift](Sources/ContextCard/TextProcessing.swift)

- Divide a frase em tokens.
- Preserva contrações como `can't`.
- Ignora pontuação.
- Permite selecionar uma ou mais palavras.
- Aceita palavras compostas.
- Destaca a seleção em HTML.
- Mantém os intervalos originais da frase para destacar somente o texto correto.

Essa é uma parte de lógica pura e pode ser portada quase diretamente para C#.

### 2.6 Tradução e explicação contextual

Arquivos principais: [Services.swift](Sources/ContextCard/Services.swift) e [Models.swift](Sources/ContextCard/Models.swift)

A geração produz:

- tradução completa da frase para português brasileiro;
- tradução da palavra ou expressão selecionada;
- explicação contextual do significado em português.

O serviço remoto usa uma API compatível com Chat Completions e solicita JSON estruturado. Existe também um serviço local de demonstração, com traduções fictícias e um pequeno dicionário de palavras.

### 2.7 Geração de áudio

Arquivo principal: [Services.swift](Sources/ContextCard/Services.swift)

Com API key:

- envia a frase para um serviço de Text-to-Speech;
- recebe áudio MP3;
- salva o arquivo temporariamente;
- adiciona o áudio ao cartão do Anki.

Sem API key:

- usa `/usr/bin/say` do macOS;
- gera um arquivo AIFF local.

No Windows, o fallback nativo seria `Windows.Media.SpeechSynthesis`. Também é possível manter o TTS da OpenAI para obter qualidade semelhante entre macOS e Windows.

### 2.8 Preview e edição do cartão

Arquivos principais: [Models.swift](Sources/ContextCard/Models.swift) e [Views.swift](Sources/ContextCard/Views.swift)

O usuário pode revisar e editar:

- frente em inglês;
- tradução da frase;
- tradução da palavra;
- significado contextual.

O HTML gerado:

- coloca a palavra inglesa selecionada em negrito na frente;
- coloca a tradução correspondente em negrito no verso;
- escapa caracteres HTML para evitar conteúdo inválido.

### 2.9 Copiar para o Anki

Arquivo principal: [CardComposerModel.swift](Sources/ContextCard/CardComposerModel.swift)

O conteúdo copiado para o clipboard é uma representação textual contendo `Front` e `Back`, incluindo as tags HTML.

Para a versão Windows, é recomendável copiar simultaneamente:

- texto simples;
- HTML formatado.

Isso torna a colagem em campos compatíveis mais confiável.

### 2.10 Envio direto para o Anki

Arquivo principal: [Services.swift](Sources/ContextCard/Services.swift)

O aplicativo:

- conecta em `http://127.0.0.1:8765`;
- verifica a conexão;
- cria o deck se necessário;
- usa o modelo `Basic`;
- preenche os campos `Front` e `Back`;
- adiciona as tags `contextcard` e `english`;
- permite duplicatas;
- anexa o áudio ao campo `Front`.

Essa integração é independente do sistema operacional. No Windows, será necessário instalar o Anki e o AnkiConnect, além de manter o Anki aberto durante o envio.

### 2.11 Fila offline

Arquivos principais: [CardQueue.swift](Sources/ContextCard/CardQueue.swift) e [CardComposerModel.swift](Sources/ContextCard/CardComposerModel.swift)

- Salva cartões pendentes em JSON.
- Copia os áudios para uma pasta persistente.
- Evita duplicatas por deck, frase e palavra-chave.
- Sincroniza cartões pendentes.
- Move falhas para uma fila de erros.
- Permite tentar novamente.
- Permite editar cartões pendentes.
- Permite apagar cartões e arquivos de áudio.

No Windows, os dados podem ficar em `%LocalAppData%\\ContextCard`, usando JSON ou SQLite.

### 2.12 Configurações

Arquivo principal: [Views.swift](Sources/ContextCard/Views.swift)

Atualmente existem configurações para:

- endpoint de tradução;
- modelo de tradução;
- API key;
- modelo de voz;
- voz utilizada;
- visibilidade dos botões principais.

O macOS usa `UserDefaults` para configurações comuns e Keychain para a API key.

No Windows, a API key deve ser armazenada no Windows Credential Manager ou protegida com DPAPI. Configurações comuns podem ser salvas em JSON.

## 3. Matriz de viabilidade no Windows 11

| Funcionalidade | Viabilidade | Alternativa Windows |
|---|---:|---|
| Interface de bandeja | Alta | WPF + integração Win32/system tray |
| Digitação de texto | Alta | WPF `TextBox`/editor multiline |
| Clipboard de texto | Alta | `System.Windows.Clipboard` |
| Clipboard de imagem | Alta | `Clipboard.ContainsImage()` e `GetImage()` |
| Importação de imagem | Alta | `OpenFileDialog` |
| OCR | Alta | `Windows.Media.Ocr.OcrEngine` |
| Gravação de voz | Alta | `MediaCapture`, `AudioGraph` ou biblioteca de áudio |
| Transcrição local | Alta, com ressalvas | `SpeechRecognizer` |
| Transcrição via OpenAI | Alta | `/v1/audio/transcriptions` |
| Tradução via API | Alta | `HttpClient` + `System.Text.Json` |
| TTS local | Alta | `SpeechSynthesizer` |
| TTS via OpenAI | Alta | `/v1/audio/speech` |
| Reprodução de áudio | Alta | `MediaPlayer` |
| Preview HTML | Alta | lógica equivalente em C# |
| Copiar para Anki | Alta | clipboard WPF com texto e HTML |
| Envio direto ao Anki | Alta | AnkiConnect via HTTP |
| Fila offline | Alta | JSON ou SQLite |
| Configurações | Alta | JSON/registro + Credential Manager/DPAPI |
| Paridade visual exata com macOS | Média | nova implementação XAML/WPF |

## 4. Requisitos funcionais para a versão Windows

### Entrada e composição

- Digitar ou colar uma frase em inglês.
- Colar uma imagem e extrair texto dela.
- Importar uma imagem do disco.
- Gravar voz e obter transcrição em inglês.
- Selecionar uma ou mais palavras-chave.
- Exibir a seleção destacada.

### Geração

- Gerar tradução da frase.
- Gerar tradução da palavra.
- Gerar significado contextual.
- Gerar áudio da frase.
- Permitir editar todos os campos antes do envio.

### Exportação

- Copiar frente e verso para o clipboard.
- Enviar diretamente ao AnkiConnect.
- Criar o deck quando necessário.
- Incluir áudio e tags.

### Operação offline

- Salvar cartão completo localmente.
- Detectar duplicatas.
- Sincronizar posteriormente.
- Mostrar erros individuais.
- Tentar novamente.
- Editar e apagar itens da fila.

### Configuração e segurança

- Configurar endpoints e modelos.
- Configurar voz.
- Configurar deck e modelo do Anki no futuro.
- Ativar/desativar botões.
- Armazenar credenciais com proteção do Windows.
- Não embutir uma API key pessoal no executável.

## 5. Arquitetura recomendada

```text
ContextCard.Core
 ├── CardDraft
 ├── TextProcessing
 ├── Translation DTOs
 ├── Queue models
 └── regras de negócio

ContextCard.Windows
 ├── Interface WPF
 ├── System tray
 ├── Clipboard
 ├── OCR
 ├── Microfone e transcrição
 ├── TTS e reprodução
 ├── Armazenamento seguro
 └── AnkiConnect
```

Interfaces sugeridas:

- `ITranslationService`
- `ISpeechRecognitionService`
- `ISpeechSynthesisService`
- `IOcrService`
- `IAnkiService`
- `ISecretStore`
- `IQueueStore`

O projeto deve usar uma instância compartilhada de `HttpClient`, timeout explícito, cancelamento, tratamento de erros HTTP e logs sem dados sensíveis.

## 6. Pontos a melhorar antes ou durante o port

- O deck atualmente é fixo como `Anki Create English`.
- O modelo do Anki é fixo como `Basic`.
- Os campos do Anki são fixos como `Front` e `Back`.
- A seleção do deck não é persistida.
- A cópia atual fornece HTML dentro de texto simples, sem formato HTML separado.
- Há poucos testes para HTTP, AnkiConnect, fila e armazenamento seguro.
- A mensagem das configurações ainda informa que OCR está reservado para uma fase futura, embora já exista.
- O envio deveria validar explicitamente tradução e áudio, não apenas a existência da frase.
- Não há cancelamento explícito de requisições em andamento.
- A notificação de sincronização da fila usa uma tecnologia exclusiva do macOS.
- O carregamento de `.env` é útil no desenvolvimento, mas não deveria ser o mecanismo principal de credenciais na distribuição final.

## 7. Segurança da API key

O aplicativo atual armazena a chave no Keychain, mas chama diretamente a API a partir do aplicativo cliente. Para uma ferramenta pessoal ou familiar, é possível permitir que cada pessoa informe a própria chave.

Para uma distribuição pública, o ideal seria:

- cada usuário utilizar sua própria chave;
- usar uma chave de projeto com limite de gasto;
- nunca embutir a chave no executável;
- não compartilhar a chave pessoal do desenvolvedor;
- considerar um backend próprio caso o aplicativo venha a ser distribuído para muitas pessoas.

A OpenAI recomenda não distribuir chaves de API em aplicativos cliente e recomenda controles de acesso, rotação e limites de gasto.

## 8. Distribuição

Para o primeiro uso pela irmã:

- publicar para `win-x64`;
- usar .NET autocontido;
- criar um instalador simples;
- instalar o aplicativo por usuário;
- documentar a instalação do AnkiConnect;
- começar com atualizações manuais.

Para uma distribuição mais profissional:

- MSIX;
- assinatura digital;
- atualizações automáticas;
- eventual publicação na Microsoft Store.

## 9. Resultado final

A versão Windows 11 é tecnicamente viável em todas as áreas principais. Não é necessário abandonar as funcionalidades centrais nem reduzir o produto a uma versão simplificada.

O trabalho será uma reimplementação das camadas específicas do macOS, mantendo a mesma ideia, os mesmos dados e o mesmo fluxo de criação de cartões.

O caminho recomendado é:

1. criar um novo projeto C#/.NET 10;
2. separar o núcleo de regras de negócio da interface;
3. implementar primeiro o fluxo básico: frase → palavra → tradução → áudio → Anki;
4. adicionar fila offline;
5. adicionar clipboard e OCR;
6. adicionar transcrição local e/ou via API;
7. empacotar e testar em uma instalação limpa do Windows 11.

## 10. Referências oficiais

### Código atual do projeto

- [Package.swift](Package.swift) — define Swift 5.9 e macOS 13 como plataforma.
- [ContextCardApp.swift](Sources/ContextCard/ContextCardApp.swift) — ciclo de vida, barra de menu e painel.
- [CardComposerModel.swift](Sources/ContextCard/CardComposerModel.swift) — estado e fluxo principal.
- [Services.swift](Sources/ContextCard/Services.swift) — tradução, TTS, AnkiConnect e Keychain.
- [VoiceTranscriptionService.swift](Sources/ContextCard/VoiceTranscriptionService.swift) — gravação e reconhecimento de voz no macOS.
- [ImageOCRService.swift](Sources/ContextCard/ImageOCRService.swift) — OCR usando Vision.
- [ClipboardTextEditor.swift](Sources/ContextCard/ClipboardTextEditor.swift) — editor e colagem de imagens.
- [TextProcessing.swift](Sources/ContextCard/TextProcessing.swift) — tokenização e HTML.
- [Models.swift](Sources/ContextCard/Models.swift) — modelo de cartão e erros.
- [CardQueue.swift](Sources/ContextCard/CardQueue.swift) — fila offline.
- [Views.swift](Sources/ContextCard/Views.swift) — interface, preview, fila e configurações.
- [ImageOCRServiceTests.swift](Tests/ContextCardTests/ImageOCRServiceTests.swift) — teste de OCR.
- [TextProcessingTests.swift](Tests/ContextCardTests/TextProcessingTests.swift) — testes de tokenização e HTML.

### Windows e .NET

- [Windows App SDK](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/) — plataforma para aplicativos desktop Windows; suporta WinUI 3, WPF, Windows Forms e Win32.
- [Escolha do caminho de desenvolvimento para Windows](https://learn.microsoft.com/en-us/windows/apps/get-started/) — recomenda WinUI 3 para novos aplicativos nativos e reconhece WPF como framework desktop maduro.
- [Clipboard.ContainsImage no WPF](https://learn.microsoft.com/en-us/dotnet/api/system.windows.clipboard.containsimage) — verifica se o clipboard contém imagem.
- [Diálogos comuns no WPF](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/windows/how-to-open-common-system-dialog-box) — `OpenFileDialog` e outros diálogos nativos.
- [OcrEngine](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.ocrengine) — OCR nativo do Windows.
- [SpeechRecognizer](https://learn.microsoft.com/en-us/uwp/api/windows.media.speechrecognition.speechrecognizer) — reconhecimento de voz, sessões contínuas e hipóteses parciais.
- [Reconhecimento de fala](https://learn.microsoft.com/en-us/windows/uwp/ui-input/speech-recognition) — requisitos de microfone, idioma e permissões.
- [AudioGraph](https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/audio-graphs) — captura e processamento de áudio em C#.
- [SpeechSynthesis](https://learn.microsoft.com/en-us/uwp/api/windows.media.speechsynthesis) — conversão de texto em fala usando vozes instaladas.
- [SpeechSynthesizer.SynthesizeTextToStreamAsync](https://learn.microsoft.com/en-us/uwp/api/windows.media.speechsynthesis.speechsynthesizer.synthesizetexttostreamasync) — geração de áudio a partir de texto.
- [MediaPlayer](https://learn.microsoft.com/en-us/windows/apps/develop/media-playback/play-audio-and-video-with-mediaplayer) — reprodução de áudio e vídeo.
- [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core) — ciclo de suporte do .NET; .NET 10 é LTS.

### APIs de IA

- [OpenAI Audio — Create speech](https://platform.openai.com/docs/api-reference/audio/voice-consent-list) — TTS, formatos de áudio, modelos e vozes.
- [OpenAI Audio — Create transcription](https://platform.openai.com/docs/api-reference/audio/verbose-json-object) — transcrição de arquivos de áudio e streaming.
- [OpenAI Models](https://platform.openai.com/docs/models/whisper) — catálogo atual de modelos de transcrição e voz.
- [OpenAI — boas práticas para segurança de API keys](https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety) — recomendações sobre armazenamento, rotação, limites e não distribuição de chaves em aplicativos cliente.

### Anki

- [Repositório oficial do AnkiConnect](https://github.com/FooSoft/anki-connect) — API HTTP local para criar notas, decks e anexar mídia ao Anki.

### Empacotamento

- [Empacotamento e distribuição de aplicativos Windows](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/) — MSIX, aplicativos autocontidos e opções de distribuição.
- [Visão geral de packaging](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/) — diferenças entre aplicativos empacotados e não empacotados.
- [Distribuição autocontida do Windows App SDK](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps) — distribuição das dependências junto com o aplicativo.
- [Distribuição de aplicativo WinUI 3 não empacotado](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/unpackage-winui-app) — executável único e limitações de distribuição.
- [Publicação de aplicativo Windows](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/publish-first-app) — publicação de WinUI 3, WPF e WinForms.
- [Aplicativos single-file no .NET](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview) — publicação de executáveis autocontidos por arquitetura.
