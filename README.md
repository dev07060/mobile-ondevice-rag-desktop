# Local Gemma macOS

[🇰🇷 한국어 (Korean)](README_ko.md)

RAG (Retrieval-Augmented Generation) + Ollama LLM integration application running locally on macOS.

## 📋 Requirements

- **macOS** (Apple Silicon or Intel)
- **Flutter** 3.9.0 or higher
- **Dart SDK** 3.9.2 or higher
- **Ollama** (for running local LLM)

## ✨ Features

- **Local RAG**: Chat with your documents completely offline.
- **Privacy First**: No data leaves your device.
- **Multi-Format Support**: Support for PDF, DOCX, Markdown (.md), and Text (.txt) files.
- **Knowledge Graph**: Visualize connections between your documents.
- **Slash Commands**: Quick actions like `/summary`, `/define`, and `/more`.

## 🚀 Installation

### 1. Install Ollama

Ollama is required to run the LLM locally.

> ✅ Ollama runs **completely locally** and does not require an API key or account.

```bash
# Install using Homebrew
brew install ollama

# Or download directly from the official website
# https://ollama.ai/download
```

After installing Ollama, start the service:

```bash
ollama serve
```

### 2. Download LLM Model

You can download models directly via the **Model Setup** screen within the app.

Alternatively, you can download them via terminal:

```bash
# Gemma 3 Model (Recommended)
ollama pull gemma3

# Or choose other models
ollama pull llama3.2
ollama pull mistral
```

### 3. Run Application

Run the app while Ollama is running:

```bash
# Run the built app or in development environment:
flutter run -d macos
```

flutter run -d macos
```

## 💡 Usage

### Adding Documents
- Click the **Attachment (📎)** button in the chat input area.
- Select **PDF**, **DOCX**, **Markdown (.md)**, or **Text (.txt)** files.
- The document will be processed and added to the local knowledge base.

### Slash Commands
Type `/` in the input field to see available commands:
- `/summary`: Summarize the retrieved context.
- `/define`: Get definitions of terms.
- `/more`: Request detailed expansion.

### Settings Menu
Click the ⚙️ icon in the home screen or app bar to access settings:
- **Clear Documents**: Reset the database to remove all stored documents.
- **Change Model**: Switch between downloaded Ollama models.
- **Restart Ollama**: Restart the local Ollama server if connection is lost.

---

## 🛠️ Developer Setup

If building from source code, follow these additional steps.

### 1. Download Embedding Model

> ℹ️ **Note**: The embedding model is bundled with the built app, so general users do not need to download it separately.

```bash
# Run in project directory
chmod +x download_models.sh
./download_models.sh
```

> ⚠️ The model file size is about 560MB, so downloading may take some time.

### 2. Install Flutter Dependencies

```bash
flutter pub get
```

### 3. Build and Run Application

```bash
flutter run -d macos
```

## 📁 Project Structure

```
local-gemma-macos/
├── lib/                    # Dart source code
├── assets/                 # Embedding model files
│   ├── bge-m3-int8.onnx   # BGE-m3 ONNX model
│   └── bge-m3-tokenizer.json
├── macos/                  # macOS platform configuration
└── download_models.sh      # Model download script
```

## 🔧 Troubleshooting

### Ollama Connection Error

Check if the Ollama service is running:

```bash
# Check Ollama status
ollama list

# Restart service
ollama serve
```

### Missing Model Files

Run the `download_models.sh` script again to download the model files.

### Flutter Build Error

```bash
# Clean build
flutter clean
flutter pub get
flutter run -d macos
```

## 📖 References

- [Flutter Official Documentation](https://docs.flutter.dev/)
- [Ollama Official Documentation](https://ollama.ai/)
- [BGE-m3 Model Info](https://huggingface.co/BAAI/bge-m3)
