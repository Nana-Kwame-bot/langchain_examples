import 'dart:io';
import 'package:langchain/langchain.dart';
import 'package:langchain_chroma/langchain_chroma.dart';
import 'package:langchain_community/langchain_community.dart';
import 'package:langchain_ollama/langchain_ollama.dart';

void main() async {
  // Initialize embeddings using Ollama
  final embeddings = OllamaEmbeddings(model: 'nomic-embed-text');

  // Initialize vector store (using Chroma in this example)
  final vectorStore = Chroma(
    embeddings: embeddings,
    collectionName: 'hormozi_transcripts',
  );

  // Load and split documents (simulating the Python indexer.py approach)
  final loader = DirectoryLoader('../hormozi_transcripts', glob: '**/*.txt');
  final documents = await loader.load();

  print("documents: ${documents.map((e) => e.id)}");

  // Split documents
  final textSplitter = RecursiveCharacterTextSplitter(
    chunkSize: 1500,
    chunkOverlap: 300,
  );
  final splitDocuments = textSplitter.splitDocuments(documents);

  // Add documents to vector store
  await vectorStore.addDocuments(documents: splitDocuments);

  // Initialize chat model
  final chatModel = ChatOllama(
    defaultOptions: ChatOllamaOptions(model: 'gemma2', temperature: 0),
  );

  // Create retriever
  final retriever = vectorStore.asRetriever(
    defaultOptions: VectorStoreRetrieverOptions(
        searchType: VectorStoreSearchType.similarity(k: 5)),
  );

  // Create RAG prompt template
  final ragPromptTemplate = ChatPromptTemplate.fromTemplates([
    (
      ChatMessageType.system,
      '''Answer the question based only on the following context. If the context is empty, say you're unable to find an answer.
Provide a clear, concise answer using full sentences.
If the context doesn't contain the answer, say you're unable to find an answer.

CONTEXT:
{context}

QUESTION: {question}'''
    ),
    (ChatMessageType.human, '{question}'),
  ]);

  // Create RAG chain
  final ragChain = Runnable.fromMap<String>({
    'context': retriever.pipe(Runnable.mapInput<List<Document>, String>(
        (docs) => docs.map((doc) => doc.pageContent).join('\n---\n'))),
    'question': Runnable.passthrough(),
  }).pipe(ragPromptTemplate).pipe(chatModel).pipe(StringOutputParser());

  // CLI interaction loop
  print('Local RAG CLI Application');
  print('Type your question (or "quit" to exit):');

  while (true) {
    stdout.write('> ');
    final userInput = stdin.readLineSync()?.trim();

    if (userInput == null || userInput.toLowerCase() == 'quit') {
      break;
    }

    try {
      print('\nThinking...\n');
      final once = await ragChain.invoke(userInput);
      print("once: $once");

      final stream = ragChain.stream(userInput);
      await for (final chunk in stream) {
        print("chunk: $chunk");
        stdout.write(chunk);
      }
      print('\n');
    } catch (e) {
      print('Error processing your question: $e');
    }
  }

  print('\nThank you for using Local RAG CLI!');
}

// Utility function to load documents from a directory
// class DirectoryLoader {
//   final String path;
//   final String glob;

//   DirectoryLoader({required this.path, required this.glob});

//   Future<List<Document>> load() async {
//     final directory = Directory(path);
//     final files = await directory
//         .list(recursive: true)
//         .where((file) =>
//             file is File && file.path.contains(glob.replaceAll('**/', '')))
//         .toList();

//     final documents = <Document>[];
//     for (final file in files) {
//       final content = await (file as File).readAsString();
//       documents.add(Document(
//         pageContent: content,
//         metadata: {'source': file.path},
//       ));
//     }

//     return documents;
//   }
// }