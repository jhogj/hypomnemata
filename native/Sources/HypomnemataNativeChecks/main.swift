import AppKit
import Foundation
import GRDB
import HypomnemataAI
import HypomnemataCore
import HypomnemataData
import HypomnemataIngestion
import HypomnemataMedia

@main
struct HypomnemataNativeChecks {
    static func main() async throws {
        try checkCore()
        try await checkAI()
        try checkData()
        try checkMedia()
        try checkPerformance()
        print("HypomnemataNativeChecks: ok")
    }

    private static func checkCore() throws {
        precondition(KindInference.infer(urlString: "https://x.com/user/status/1") == .tweet)
        precondition(KindInference.infer(urlString: "https://twitter.com/user/status/1") == .tweet)
        precondition(KindInference.infer(urlString: "https://www.youtube.com/watch?v=abc") == .video)
        precondition(KindInference.infer(urlString: "https://youtu.be/abc") == .video)
        precondition(KindInference.infer(urlString: "https://vimeo.com/123456") == .video)
        precondition(KindInference.infer(urlString: "https://example.com/report.pdf") == .pdf)
        precondition(KindInference.infer(urlString: "https://example.com/photo.webp") == .image)
        precondition(KindInference.infer(urlString: "https://example.com/news/story") == .article)
        precondition(KindInference.infer(urlString: nil, filename: "clip.mov") == .video)

        let validURLDraft = try CapturePlanner.validate(CaptureDraft(
            sourceURL: "  https://example.com/news/story  ",
            title: "  Matéria  ",
            note: "  nota  ",
            tags: [" Dev ", "dev", "Leitura"]
        ))
        precondition(validURLDraft.sourceURL == "https://example.com/news/story")
        precondition(validURLDraft.title == "Matéria")
        precondition(validURLDraft.note == "nota")
        precondition(validURLDraft.tags == ["dev", "leitura"])

        let urlPlan = try CapturePlanner.validateAndPlan(CaptureDraft(sourceURL: "https://youtu.be/abc"))
        precondition(urlPlan.1.kind == .video)
        precondition(urlPlan.1.jobs == [.downloadMedia, .summarize, .autotag])

        let tweetPlan = try CapturePlanner.validateAndPlan(CaptureDraft(sourceURL: "https://x.com/user/status/1"))
        precondition(tweetPlan.1.kind == .tweet)
        precondition(tweetPlan.1.jobs == [.downloadMedia, .generateThumbnail])

        let pdfPlan = try CapturePlanner.validateAndPlan(CaptureDraft(fileURL: URL(fileURLWithPath: "/tmp/documento.pdf")))
        precondition(pdfPlan.1.kind == .pdf)
        precondition(pdfPlan.1.jobs == [.generateThumbnail, .runOCR, .summarize, .autotag])

        let textPlan = try CapturePlanner.validateAndPlan(CaptureDraft(bodyText: "texto solto"))
        precondition(textPlan.1.kind == .note)
        precondition(textPlan.1.jobs.isEmpty)

        do {
            _ = try CapturePlanner.validate(CaptureDraft(sourceURL: "example.com/noticia"))
            preconditionFailure("URL without http/https was accepted.")
        } catch CaptureValidationError.invalidURL(_) {
            // Expected: URL captures must be explicit web URLs.
        }

        do {
            _ = try CapturePlanner.validate(CaptureDraft())
            preconditionFailure("Empty capture was accepted.")
        } catch CaptureValidationError.missingInput {
            // Expected: capture needs one source.
        }

        do {
            _ = try CapturePlanner.validate(CaptureDraft(sourceURL: "https://example.com", bodyText: "texto"))
            preconditionFailure("Capture with multiple sources was accepted.")
        } catch CaptureValidationError.multipleInputs {
            // Expected: capture source must be unambiguous.
        }

        let missingDependencyError = JobDependencyResolver(
            doctor: DependencyDoctor(
                environment: ["PATH": "/tmp/hypomnemata-no-tools"],
                includeDefaultSearchPaths: false
            )
        ).missingDependencyError(for: .scrapeArticle)
        precondition(missingDependencyError?.contains("trafilatura") == true)
        precondition(missingDependencyError?.contains("brew install trafilatura") == true)

        let nativeOCRDependencyError = JobDependencyResolver(
            doctor: DependencyDoctor(
                environment: ["PATH": "/tmp/hypomnemata-no-tools"],
                includeDefaultSearchPaths: false
            )
        ).missingDependencyError(for: .runOCR)
        precondition(nativeOCRDependencyError == nil)

        let subprocess = SubprocessRunner(environment: ["PATH": "/bin:/usr/bin"])
        let subprocessResult = try subprocess.run(
            executable: "sh",
            arguments: ["-c", "printf stdout; printf stderr >&2"]
        )
        precondition(subprocessResult.exitCode == 0)
        precondition(String(data: subprocessResult.stdout, encoding: .utf8) == "stdout")
        precondition(String(data: subprocessResult.stderr, encoding: .utf8) == "stderr")

        do {
            _ = try SubprocessRunner(environment: ["PATH": "/tmp/hypomnemata-no-tools"])
                .resolve(executable: "definitely-not-installed")
            preconditionFailure("Missing executable should fail before Process.run.")
        } catch SubprocessRunnerError.executableNotFound("definitely-not-installed") {
            // Expected: subprocess executables are resolved through PATH.
        }

        let text = "Veja [[018f73ba-9f9d-7a0d-8ac2-f28f82cf1296|Nome atual]] e texto"
        precondition(LinkParser.references(in: text) == [
            ItemLinkReference(targetID: "018f73ba-9f9d-7a0d-8ac2-f28f82cf1296", displayText: "Nome atual"),
        ])

        let id = UUIDV7.generateString()
        precondition(id.count == 36)
        precondition(id[id.index(id.startIndex, offsetBy: 14)] == "7")
        precondition(["8", "9", "a", "b"].contains(id[id.index(id.startIndex, offsetBy: 19)]))
    }

    private static func checkAI() async throws {
        let configured = try LLMConfiguration.fromEnvironment([
            "HYPO_LLM_URL": "http://127.0.0.1:8080",
            "HYPO_LLM_MODEL": "modelo-local",
            "HYPO_LLM_CONTEXT_LIMIT": "1200",
        ])
        precondition(configured.baseURL.absoluteString == "http://127.0.0.1:8080")
        precondition(configured.model == "modelo-local")
        precondition(configured.contextCharacterLimit == 1200)

        do {
            _ = try LLMConfiguration.fromEnvironment([
                "HYPO_LLM_URL": "nota-url",
                "HYPO_LLM_MODEL": "modelo-local",
            ])
            preconditionFailure("Invalid LLM URL was accepted.")
        } catch LLMConfigurationError.invalidBaseURL {
            // Expected: provider URL must be explicit http/https.
        }

        do {
            _ = try LLMConfiguration.fromEnvironment([
                "HYPO_LLM_URL": "http://127.0.0.1:8080",
                "HYPO_LLM_MODEL": " ",
            ])
            preconditionFailure("Empty LLM model was accepted.")
        } catch LLMConfigurationError.emptyModel {
            // Expected: a provider model is required.
        }

        let context = LLMItemContext(
            title: "Título",
            note: "Nota curta",
            bodyText: String(repeating: "abc", count: 100)
        )
        let promptContext = try context.promptContext(limit: 12)
        precondition(promptContext == "abcabcabcabc")

        do {
            _ = try LLMItemContext().promptContext(limit: 10)
            preconditionFailure("Empty item context was accepted for LLM.")
        } catch LLMClientError.emptyContent {
            // Expected: LLM jobs need usable item content.
        }

        let fake = FakeLLMClient(response: "Resumo controlado")
        let response = try await fake.complete(messages: [
            LLMMessage(role: "system", content: "Resuma"),
            LLMMessage(role: "user", content: promptContext),
        ])
        precondition(response == "Resumo controlado")
        precondition(fake.lastMessages?.last?.content == promptContext)

        let mapper = LLMRecoverableErrorMapper()
        let message = mapper.jobErrorMessage(for: LLMClientError.providerStatus(503))
        precondition(message.contains("Falha recuperável de IA"))
        precondition(message.contains("HTTP 503"))
        let ingestionMessage = mapper.jobErrorMessage(for: MediaDownloadError.binaryFailed(exitCode: 1, message: "HTTP 429"))
        precondition(ingestionMessage.contains("Falha recuperável de ingestão"))
        precondition(ingestionMessage.contains("HTTP 429"))

        let summaryClient = FakeLLMClient(response: "Resumo controlado")
        let summaryService = ItemAIService(client: summaryClient, configuration: configured)
        let generatedSummary = try await summaryService.summarize(context: context)
        precondition(generatedSummary == "Resumo controlado")
        precondition(summaryClient.lastMessages?.first?.role == "system")
        precondition(summaryClient.lastMessages?.last?.content.contains("abcabc") == true)

        let streamingClient = FakeLLMClient(response: "Resumo em streaming.")
        let streamingService = ItemAIService(client: streamingClient, configuration: configured)
        let summaryStream = try streamingService.streamSummary(context: context)
        var streamedSummary = ""
        for try await chunk in summaryStream {
            streamedSummary += chunk
        }
        precondition(streamedSummary == "Resumo em streaming.")
        precondition(streamingClient.lastMessages?.first?.role == "system")
        precondition(streamingClient.lastMessages?.last?.role == "user")
        precondition(streamingClient.lastMessages?.last?.content.contains("abcabc") == true)

        do {
            _ = try streamingService.streamSummary(context: LLMItemContext(
                title: nil,
                note: nil,
                bodyText: nil
            ))
            preconditionFailure("streamSummary deve falhar quando não há conteúdo.")
        } catch LLMClientError.emptyContent {
            // Expected: streaming exige conteúdo, igual ao summarize síncrono.
        }

        let tagClient = FakeLLMClient(response: #"["Filosofia", "Leitura", "dev"]"#)
        let tagService = ItemAIService(client: tagClient, configuration: configured)
        let generatedTags = try await tagService.autotags(context: context, existingTags: ["Dev"])
        precondition(generatedTags == ["dev", "filosofia", "leitura"])

        let looseTags = ItemAIService.normalizedTags(from: " #Swift,\nIA local, swift ", existingTags: ["Mac"])
        precondition(looseTags == ["mac", "swift", "ia local"])

        precondition(JobAutomation.canRun(.summarize))
        precondition(JobAutomation.canRun(.autotag))
        precondition(JobAutomation.canRun(.scrapeArticle))
        precondition(JobAutomation.canRun(.downloadMedia))
        precondition(JobAutomation.canRun(.generateThumbnail))
        precondition(!JobAutomation.canRun(.runOCR))

        let summaryAutomation = JobAutomation(
            service: ItemAIService(
                client: FakeLLMClient(response: "Resumo automático"),
                configuration: configured
            )
        )
        let articleItem = Item(
            kind: .article,
            title: "Artigo",
            bodyText: "Conteúdo razoável para resumo automático.",
            tags: []
        )
        let summaryOutcome = try await summaryAutomation.run(.summarize, on: articleItem)
        guard case let .summarized(summaryText) = summaryOutcome else {
            preconditionFailure("Summarize outcome should be .summarized")
        }
        precondition(summaryText == "Resumo automático")

        let autotagAutomation = JobAutomation(
            service: ItemAIService(
                client: FakeLLMClient(response: #"["politica","etica"]"#),
                configuration: configured
            )
        )
        let autotagOutcome = try await autotagAutomation.run(.autotag, on: articleItem)
        guard case let .taggedAutomatically(autoTags) = autotagOutcome else {
            preconditionFailure("Autotag outcome should be .taggedAutomatically")
        }
        precondition(autoTags == ["politica", "etica"])

        let itemWithTags = Item(
            kind: .article,
            title: "Já tem tag",
            bodyText: "Conteúdo qualquer",
            tags: ["existente"]
        )
        let conservativeOutcome = try await autotagAutomation.run(.autotag, on: itemWithTags)
        guard case .skipped = conservativeOutcome else {
            preconditionFailure("Autotag should skip when item already has tags")
        }

        let emptyContextItem = Item(kind: .note, title: nil, bodyText: nil, tags: [])
        let emptyOutcome = try await summaryAutomation.run(.summarize, on: emptyContextItem)
        guard case .skipped = emptyOutcome else {
            preconditionFailure("Summarize should skip when there is no content")
        }

        do {
            _ = try await JobAutomation().run(.summarize, on: articleItem)
            preconditionFailure("summarize without configured LLM service should fail.")
        } catch JobAutomationError.missingExecutor(.summarize) {
            // Expected: AI jobs still require the LLM service.
        }

        do {
            _ = try await summaryAutomation.run(.scrapeArticle, on: articleItem)
            preconditionFailure("scrapeArticle without configured scraper should fail.")
        } catch JobAutomationError.missingExecutor(.scrapeArticle) {
            // Expected: sem ArticleScraper configurado, o job falha de forma identificável.
        }

        do {
            _ = try await summaryAutomation.run(.downloadMedia, on: articleItem)
            preconditionFailure("downloadMedia without configured downloader should fail.")
        } catch JobAutomationError.missingExecutor(.downloadMedia) {
            // Expected: sem MediaDownloader configurado, o job falha de forma identificável.
        }

        do {
            _ = try await summaryAutomation.run(.generateThumbnail, on: articleItem)
            preconditionFailure("generateThumbnail without configured fetcher should fail.")
        } catch JobAutomationError.missingExecutor(.generateThumbnail) {
            // Expected: sem RemoteThumbnailFetcher configurado, o job falha de forma identificável.
        }

        let scrapedFixture = ArticleScrapeResult(
            title: "Título extraído",
            bodyText: String(repeating: "Texto razoável de artigo. ", count: 12),
            description: "Resumo curto do artigo.",
            author: "Autor X",
            sitename: "Site Y",
            publishedAt: "2026-04-25",
            heroImageURL: "https://example.com/hero.jpg",
            heroImage: ArticleHeroImage(
                data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
                mimeType: "image/jpeg",
                originalFilename: "hero.jpg"
            )
        )
        let scraperAutomation = JobAutomation(
            service: ItemAIService(
                client: FakeLLMClient(response: "Resumo automático"),
                configuration: configured
            ),
            articleScraper: FakeArticleScraper(result: scrapedFixture, expectedURL: "https://example.com/post")
        )
        let articleURLItem = Item(
            kind: .article,
            sourceURL: "https://example.com/post",
            title: nil,
            bodyText: nil,
            tags: []
        )
        let scrapedOutcome = try await scraperAutomation.run(.scrapeArticle, on: articleURLItem)
        guard case let .articleScraped(scraped) = scrapedOutcome else {
            preconditionFailure("scrapeArticle outcome deve ser .articleScraped.")
        }
        precondition(scraped.title == "Título extraído")
        precondition((scraped.bodyText ?? "").count >= 200)
        precondition(scraped.heroImage?.data == Data([0xFF, 0xD8, 0xFF, 0xE0]))
        precondition(scraped.heroImage?.mimeType == "image/jpeg")

        let ingestionOnlyAutomation = JobAutomation(
            articleScraper: FakeArticleScraper(result: scrapedFixture, expectedURL: "https://example.com/post")
        )
        let ingestionOnlyOutcome = try await ingestionOnlyAutomation.run(.scrapeArticle, on: articleURLItem)
        guard case .articleScraped = ingestionOnlyOutcome else {
            preconditionFailure("Ingestion jobs must run without an LLM service.")
        }

        let articleURLEmpty = Item(
            kind: .article,
            sourceURL: "  ",
            title: nil,
            bodyText: nil,
            tags: []
        )
        do {
            _ = try await scraperAutomation.run(.scrapeArticle, on: articleURLEmpty)
            preconditionFailure("scrapeArticle deve falhar quando o item não tem URL.")
        } catch JobAutomationError.missingSourceURL {
            // Expected.
        }

        let scrapeStub = TrafilaturaArticleScraper(
            trafilaturaPath: "/usr/bin/false",
            renderer: nil,
            imageDownloader: { _ in (Data(), nil) },
            runProcess: { _, _, _ in
                let json = #"{"title":"Stub","text":"\#(String(repeating: "Conteudo. ", count: 30))","image":"https://example.com/stub.jpg"}"#
                return SubprocessResult(exitCode: 0, stdout: Data(json.utf8), stderr: Data())
            }
        )
        let parsedResult = try await scrapeStub.scrape(url: "https://example.com/stub")
        precondition(parsedResult.title == "Stub")
        precondition((parsedResult.bodyText ?? "").count >= 200)
        precondition(parsedResult.heroImageURL == "https://example.com/stub.jpg")
        precondition(parsedResult.heroImage == nil)

        let scrapeFail = TrafilaturaArticleScraper(
            trafilaturaPath: "/usr/bin/false",
            renderer: nil,
            imageDownloader: { _ in (Data(), nil) },
            runProcess: { _, _, _ in
                SubprocessResult(exitCode: 1, stdout: Data(), stderr: Data("erro fake".utf8))
            }
        )
        do {
            _ = try await scrapeFail.scrape(url: "https://example.com/x")
            preconditionFailure("Saída não-zero do trafilatura deve virar erro.")
        } catch ArticleScrapeError.binaryFailed {
            // Expected.
        }

        let scrapeEmpty = TrafilaturaArticleScraper(
            trafilaturaPath: "/usr/bin/false",
            renderer: nil,
            imageDownloader: { _ in (Data(), nil) },
            runProcess: { _, _, _ in
                let json = #"{"title":"X","text":"curto"}"#
                return SubprocessResult(exitCode: 0, stdout: Data(json.utf8), stderr: Data())
            }
        )
        do {
            _ = try await scrapeEmpty.scrape(url: "https://example.com/y")
            preconditionFailure("Texto curto sem fallback deve virar emptyContent.")
        } catch ArticleScrapeError.emptyContent {
            // Expected.
        }

        let renderedHTML = "<html><body>" + String(repeating: "<p>SPA payload</p>", count: 30) + "</body></html>"
        actor StdinCapture {
            var seen: Data = Data()
            func record(_ data: Data?) { if let data { seen = data } }
            func snapshot() -> Data { seen }
        }
        let stdinCapture = StdinCapture()
        let scrapeFallback = TrafilaturaArticleScraper(
            trafilaturaPath: "/usr/bin/false",
            renderer: FakePageRenderer(html: renderedHTML),
            imageDownloader: { _ in (Data(), nil) },
            runProcess: { _, args, stdin in
                Task { await stdinCapture.record(stdin) }
                if args.contains("--URL") {
                    let json = #"{"title":"shell","text":"curto"}"#
                    return SubprocessResult(exitCode: 0, stdout: Data(json.utf8), stderr: Data())
                }
                let json = #"{"title":"final","text":"\#(String(repeating: "fallback ok. ", count: 40))"}"#
                return SubprocessResult(exitCode: 0, stdout: Data(json.utf8), stderr: Data())
            }
        )
        let fallbackResult = try await scrapeFallback.scrape(url: "https://spa.example.com")
        precondition(fallbackResult.title == "final")
        precondition((fallbackResult.bodyText ?? "").count >= 200)
        let capturedStdin = await stdinCapture.snapshot()
        precondition(String(data: capturedStdin, encoding: .utf8)?.contains("SPA payload") == true)

        let mediaFixture = MediaDownloadResult(
            data: Data([0x00, 0x00, 0x00, 0x18]),
            mimeType: "video/mp4",
            originalFilename: "video.mp4",
            title: "Vídeo baixado",
            durationSeconds: 42,
            webpageURL: "https://youtu.be/abc",
            subtitles: [
                DownloadedSubtitle(
                    data: Data("WEBVTT".utf8),
                    mimeType: "text/vtt; charset=utf-8",
                    originalFilename: "video.pt.vtt"
                ),
            ]
        )
        let mediaAutomation = JobAutomation(
            service: ItemAIService(
                client: FakeLLMClient(response: "Resumo automático"),
                configuration: configured
            ),
            mediaDownloader: FakeMediaDownloader(result: mediaFixture, expectedURL: "https://youtu.be/abc")
        )
        let videoURLItem = Item(
            kind: .video,
            sourceURL: "https://youtu.be/abc",
            title: nil,
            bodyText: nil,
            tags: []
        )
        let mediaOutcome = try await mediaAutomation.run(.downloadMedia, on: videoURLItem)
        guard case let .mediaDownloaded(media) = mediaOutcome else {
            preconditionFailure("downloadMedia outcome deve ser .mediaDownloaded.")
        }
        precondition(media.title == "Vídeo baixado")
        precondition(media.mimeType == "video/mp4")
        precondition(media.durationSeconds == 42)
        precondition(media.subtitles.first?.originalFilename == "video.pt.vtt")

        do {
            _ = try await mediaAutomation.run(.downloadMedia, on: articleURLEmpty)
            preconditionFailure("downloadMedia deve falhar quando o item não tem URL.")
        } catch JobAutomationError.missingSourceURL {
            // Expected.
        }

        let mediaStub = YTDLPMediaDownloader(
            ytDLPPath: "/usr/bin/false",
            runProcess: { _, args, workingDirectory in
                if args.contains("--dump-json") {
                    let json = #"{"title":"Stub Video","duration":12.5,"webpage_url":"https://example.com/watch"}"#
                    return SubprocessResult(exitCode: 0, stdout: Data(json.utf8), stderr: Data())
                }
                if args.contains("--skip-download") {
                    try Data("WEBVTT\n".utf8).write(
                        to: workingDirectory.appendingPathComponent("Stub Video [abc].pt.vtt")
                    )
                    return SubprocessResult(exitCode: 0, stdout: Data(), stderr: Data())
                }
                try Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70]).write(
                    to: workingDirectory.appendingPathComponent("Stub Video [abc].mp4")
                )
                return SubprocessResult(exitCode: 0, stdout: Data(), stderr: Data())
            }
        )
        let downloadedResult = try await mediaStub.download(url: "https://example.com/watch")
        precondition(downloadedResult.title == "Stub Video")
        precondition(downloadedResult.durationSeconds == 12.5)
        precondition(downloadedResult.webpageURL == "https://example.com/watch")
        precondition(downloadedResult.mimeType == "video/mp4")
        precondition(downloadedResult.originalFilename == "Stub Video [abc].mp4")
        precondition(downloadedResult.subtitles.count == 1)
        precondition(downloadedResult.subtitles[0].mimeType == "text/vtt; charset=utf-8")

        let mediaSubtitle429 = YTDLPMediaDownloader(
            ytDLPPath: "/usr/bin/false",
            runProcess: { _, args, workingDirectory in
                if args.contains("--dump-json") {
                    let json = #"{"title":"Video Sem Legenda","duration":9}"#
                    return SubprocessResult(exitCode: 0, stdout: Data(json.utf8), stderr: Data())
                }
                if args.contains("--skip-download") {
                    return SubprocessResult(exitCode: 1, stdout: Data(), stderr: Data("HTTP Error 429: Too Many Requests".utf8))
                }
                try Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70]).write(
                    to: workingDirectory.appendingPathComponent("Video Sem Legenda [xyz].mp4")
                )
                return SubprocessResult(exitCode: 0, stdout: Data(), stderr: Data())
            }
        )
        let noSubtitleResult = try await mediaSubtitle429.download(url: "https://example.com/no-subtitle")
        precondition(noSubtitleResult.originalFilename == "Video Sem Legenda [xyz].mp4")
        precondition(noSubtitleResult.subtitles.isEmpty)

        let mediaFail = YTDLPMediaDownloader(
            ytDLPPath: "/usr/bin/false",
            runProcess: { _, _, _ in
                SubprocessResult(exitCode: 1, stdout: Data(), stderr: Data("erro yt".utf8))
            }
        )
        do {
            _ = try await mediaFail.download(url: "https://example.com/fail")
            preconditionFailure("Saída não-zero do yt-dlp deve virar erro.")
        } catch MediaDownloadError.binaryFailed {
            // Expected.
        }

        let mediaEmpty = YTDLPMediaDownloader(
            ytDLPPath: "/usr/bin/false",
            runProcess: { _, args, _ in
                if args.contains("--dump-json") {
                    return SubprocessResult(exitCode: 0, stdout: Data(#"{"title":"Sem arquivo"}"#.utf8), stderr: Data())
                }
                return SubprocessResult(exitCode: 0, stdout: Data(), stderr: Data())
            }
        )
        do {
            _ = try await mediaEmpty.download(url: "https://example.com/empty")
            preconditionFailure("Download sem arquivo de mídia deve falhar.")
        } catch MediaDownloadError.outputNotFound {
            // Expected.
        }

        let thumbnailFixture = RemoteThumbnailResult(
            data: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            mimeType: "image/jpeg",
            originalFilename: "tweet.jpg",
            sourceURL: "https://pbs.twimg.com/media/tweet.jpg"
        )
        let thumbnailAutomation = JobAutomation(
            service: ItemAIService(
                client: FakeLLMClient(response: "Resumo automático"),
                configuration: configured
            ),
            remoteThumbnailFetcher: FakeRemoteThumbnailFetcher(
                result: thumbnailFixture,
                expectedURL: "https://x.com/user/status/1"
            )
        )
        let tweetURLItem = Item(
            kind: .tweet,
            sourceURL: "https://x.com/user/status/1",
            title: nil,
            bodyText: nil,
            tags: []
        )
        let thumbnailOutcome = try await thumbnailAutomation.run(.generateThumbnail, on: tweetURLItem)
        guard case let .thumbnailFetched(thumbnail) = thumbnailOutcome else {
            preconditionFailure("generateThumbnail outcome deve ser .thumbnailFetched.")
        }
        precondition(thumbnail.mimeType == "image/jpeg")
        precondition(thumbnail.originalFilename == "tweet.jpg")

        let galleryStub = GalleryDLThumbnailFetcher(
            galleryDLPath: "/usr/bin/false",
            runProcess: { _, _, workingDirectory in
                try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(
                    to: workingDirectory.appendingPathComponent("gallery.jpg")
                )
                return SubprocessResult(exitCode: 0, stdout: Data(), stderr: Data())
            },
            fetchData: { _ in
                preconditionFailure("gallery-dl success should not call oEmbed fallback.")
            }
        )
        let galleryResult = try await galleryStub.fetchThumbnail(url: "https://x.com/user/status/2")
        precondition(galleryResult.originalFilename == "gallery.jpg")
        precondition(galleryResult.mimeType == "image/jpeg")

        let oembedStub = GalleryDLThumbnailFetcher(
            galleryDLPath: "/usr/bin/false",
            runProcess: { _, _, _ in
                SubprocessResult(exitCode: 1, stdout: Data(), stderr: Data("rate limited".utf8))
            },
            fetchData: { url in
                if url.contains("publish.twitter.com/oembed") {
                    let json = #"{"html":"<blockquote><img src=\"https://pbs.twimg.com/media/fallback.jpg\"></blockquote>"}"#
                    return (Data(json.utf8), "application/json")
                }
                precondition(url == "https://pbs.twimg.com/media/fallback.jpg")
                return (Data([0xFF, 0xD8, 0xFF, 0xD9]), "image/jpeg")
            }
        )
        let oembedResult = try await oembedStub.fetchThumbnail(url: "https://x.com/user/status/3")
        precondition(oembedResult.originalFilename == "fallback.jpg")
        precondition(oembedResult.mimeType == "image/jpeg")

        let envOnly = try LLMConfiguration.resolve(
            overrides: LLMOverrides(),
            environment: [
                "HYPO_LLM_URL": "http://env.local:9000",
                "HYPO_LLM_MODEL": "modelo-env",
                "HYPO_LLM_CONTEXT_LIMIT": "2048",
            ]
        )
        precondition(envOnly.baseURL.absoluteString == "http://env.local:9000")
        precondition(envOnly.model == "modelo-env")
        precondition(envOnly.contextCharacterLimit == 2048)

        let overridesWin = try LLMConfiguration.resolve(
            overrides: LLMOverrides(
                url: "http://override.local:7000",
                model: "modelo-vault",
                contextLimit: "9999"
            ),
            environment: [
                "HYPO_LLM_URL": "http://env.local:9000",
                "HYPO_LLM_MODEL": "modelo-env",
                "HYPO_LLM_CONTEXT_LIMIT": "2048",
            ]
        )
        precondition(overridesWin.baseURL.absoluteString == "http://override.local:7000")
        precondition(overridesWin.model == "modelo-vault")
        precondition(overridesWin.contextCharacterLimit == 9999)

        let partialOverride = try LLMConfiguration.resolve(
            overrides: LLMOverrides(model: "só-modelo"),
            environment: [
                "HYPO_LLM_URL": "http://env.local:9000",
                "HYPO_LLM_CONTEXT_LIMIT": "1500",
            ]
        )
        precondition(partialOverride.baseURL.absoluteString == "http://env.local:9000")
        precondition(partialOverride.model == "só-modelo")
        precondition(partialOverride.contextCharacterLimit == 1500)

        let trimmedOverrides = LLMOverrides(url: "  ", model: "", contextLimit: "  ")
        precondition(trimmedOverrides.url == nil)
        precondition(trimmedOverrides.model == nil)
        precondition(trimmedOverrides.contextLimit == nil)

        do {
            _ = try LLMConfiguration.resolve(
                overrides: LLMOverrides(url: "nada"),
                environment: [:]
            )
            preconditionFailure("Override URL inválida deveria falhar.")
        } catch LLMConfigurationError.invalidBaseURL {
            // Expected.
        }

        do {
            _ = try LLMConfiguration.resolve(
                overrides: LLMOverrides(contextLimit: "abc"),
                environment: [:]
            )
            preconditionFailure("Override de limite inválido deveria falhar.")
        } catch LLMConfigurationError.invalidContextLimit {
            // Expected.
        }

        let longBody = String(repeating: "Documento histórico relevante. ", count: 30)
        let chatItem = Item(
            kind: .article,
            title: "História antiga",
            bodyText: longBody,
            tags: []
        )
        precondition(ItemChatService.isAvailable(for: chatItem))
        precondition(!ItemChatService.isAvailable(for: Item(kind: .note, bodyText: "curto", tags: [])))

        let chatClient = FakeLLMClient(response: "Resposta baseada no documento.")
        let chatService = ItemChatService(client: chatClient, configuration: configured)
        let conversation = ItemChatService.Conversation(
            item: chatItem,
            history: [
                ChatMessage(itemID: chatItem.id, role: .user, content: "Olá?"),
                ChatMessage(itemID: chatItem.id, role: .assistant, content: "Olá! Em que posso ajudar?"),
            ],
            newUserMessage: "Quem escreveu o documento?"
        )
        let stream = try chatService.streamReply(conversation)
        var collected = ""
        for try await chunk in stream {
            collected += chunk
        }
        precondition(collected == "Resposta baseada no documento.")
        let lastMessages = chatClient.lastMessages ?? []
        precondition(lastMessages.first?.role == "system")
        precondition(lastMessages.first?.content.contains("História antiga") == true)
        precondition(lastMessages.contains(where: { $0.role == "user" && $0.content == "Olá?" }))
        precondition(lastMessages.contains(where: { $0.role == "assistant" && $0.content.contains("Em que posso ajudar") }))
        precondition(lastMessages.last?.role == "user")
        precondition(lastMessages.last?.content == "Quem escreveu o documento?")

        do {
            _ = try chatService.streamReply(ItemChatService.Conversation(
                item: chatItem,
                history: [],
                newUserMessage: "  "
            ))
            preconditionFailure("Mensagem vazia não deveria abrir streaming.")
        } catch LLMClientError.emptyContent {
            // Expected: pergunta vazia é rejeitada.
        }

        do {
            _ = try chatService.streamReply(ItemChatService.Conversation(
                item: Item(kind: .note, bodyText: "curto", tags: []),
                history: [],
                newUserMessage: "Pergunta válida"
            ))
            preconditionFailure("Item sem conteúdo suficiente não deveria liberar chat.")
        } catch LLMClientError.emptyContent {
            // Expected: chat exige bodyText >= 300 chars.
        }
    }

    private static func checkData() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hypomnemata-native-checks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appPaths = AppPaths(rootDirectory: root)

        let database = try NativeDatabase(
            appPaths: appPaths,
            passphrase: "test",
            requireSQLCipher: true
        )

        let repository = SQLiteItemRepository(database: database)
        let item = try repository.createItem(
            kind: .note,
            sourceURL: nil,
            title: "filosófia grega",
            note: "Sócrates",
            bodyText: nil,
            summary: nil,
            metadataJSON: nil,
            tags: ["Filosofia", "grega"]
        )
        let article = try repository.createItem(
            kind: .article,
            sourceURL: "https://example.com/platao",
            title: "Academia de Platão",
            note: nil,
            bodyText: "Diálogos políticos e teoria das ideias.",
            summary: nil,
            metadataJSON: nil,
            tags: ["filosofia", "platao"]
        )
        let bookmark = try repository.createItem(
            kind: .bookmark,
            sourceURL: "https://example.com/grdb",
            title: "GRDB",
            note: "Referência técnica",
            bodyText: nil,
            summary: nil,
            metadataJSON: nil,
            tags: ["dev"]
        )
        let folder = try repository.createFolder(name: "Estudos")
        try repository.addItems([item.id, article.id], toFolder: folder.id)
        let renamedFolder = try repository.renameFolder(id: folder.id, name: " Estudos antigos ")
        precondition(renamedFolder.name == "Estudos antigos")
        try repository.removeItems([article.id], fromFolder: folder.id)
        let articleFoldersAfterRemoval = try repository.folders(forItemID: article.id)
        precondition(articleFoldersAfterRemoval.isEmpty)
        try repository.addItems([article.id], toFolder: folder.id)
        do {
            _ = try repository.createFolder(name: " ")
            preconditionFailure("Empty folder name was accepted.")
        } catch DataError.emptyFolderName {
            // Expected: folders need a visible name.
        }
        do {
            _ = try repository.renameFolder(id: folder.id, name: " ")
            preconditionFailure("Empty folder rename was accepted.")
        } catch DataError.emptyFolderName {
            // Expected: folder rename needs a visible name.
        }

        let storedItem = try repository.item(id: item.id)
        let noteItems = try repository.listItems(filter: ItemListFilter(kind: .note))
        let searchIDs = try repository.search("filosofia").map(\.id)
        let filteredArticleIDs = try repository.listItems(
            filter: ItemListFilter(kind: .article, tag: "filosofia", folderID: folder.id)
        ).map(\.id)
        let filteredBookmarkIDs = try repository.listItems(
            filter: ItemListFilter(kind: .bookmark, tag: "filosofia", folderID: folder.id)
        ).map(\.id)
        let filteredSearchIDs = try repository.search(
            "platao",
            filter: ItemListFilter(kind: .article, tag: "filosofia", folderID: folder.id)
        ).map(\.id)
        let folders = try repository.listFolders()
        let kindCounts = try repository.itemCountsByKind()
        let tagCounts = try repository.tagCounts()
        let totalItemCount = try repository.totalItemCount()
        let jobTime = ClockTimestamp.nowISO8601()
        let plannedJobs = [
            Job(
                id: "job-a",
                itemID: article.id,
                kind: .scrapeArticle,
                payloadJSON: #"{"source_url":"https://example.com/platao"}"#,
                createdAt: jobTime,
                updatedAt: jobTime
            ),
            Job(
                id: "job-b",
                itemID: article.id,
                kind: .summarize,
                payloadJSON: #"{"source_url":"https://example.com/platao"}"#,
                createdAt: jobTime,
                updatedAt: jobTime
            ),
        ]
        try repository.insertJobs(plannedJobs)
        try repository.updateJobStatus(
            id: "job-b",
            status: .failed,
            error: "Dependência ausente: trafilatura. Rode `brew install trafilatura`."
        )
        let storedJobs = try repository.jobs(forItemID: article.id)
        precondition(storedItem.tags == ["filosofia", "grega"])
        precondition(bookmark.kind == .bookmark)
        precondition(noteItems.count == 1)
        precondition(searchIDs == [item.id])
        precondition(filteredArticleIDs == [article.id])
        precondition(filteredBookmarkIDs.isEmpty)
        precondition(filteredSearchIDs == [article.id])
        precondition(folders == [Folder(id: folder.id, name: "Estudos antigos", itemCount: 2, createdAt: folder.createdAt)])
        let itemFolders = try repository.folders(forItemID: item.id)
        precondition(itemFolders == [Folder(id: folder.id, name: "Estudos antigos", itemCount: 2, createdAt: folder.createdAt)])
        precondition(totalItemCount == 3)
        precondition(kindCounts[.note] == 1)
        precondition(kindCounts[.article] == 1)
        precondition(kindCounts[.bookmark] == 1)
        precondition(kindCounts[.video] == 0)
        precondition(tagCounts == [
            TagCount(name: "dev", count: 1),
            TagCount(name: "filosofia", count: 2),
            TagCount(name: "grega", count: 1),
            TagCount(name: "platao", count: 1),
        ])
        precondition(storedJobs.count == 2)
        precondition(storedJobs[0] == plannedJobs[0])
        precondition(storedJobs[1].id == "job-b")
        precondition(storedJobs[1].status == .failed)
        precondition(storedJobs[1].error?.contains("brew install trafilatura") == true)

        try repository.incrementJobAttempts(id: "job-b")
        try repository.updateJobStatus(id: "job-b", status: .pending, error: nil)
        let retriedJobs = try repository.jobs(forItemID: article.id)
        let retriedB = retriedJobs.first { $0.id == "job-b" }!
        precondition(retriedB.status == .pending)
        precondition(retriedB.error == nil)
        precondition(retriedB.attempts == 1)

        let llmSettings = LLMSettingsStore(database: database)
        let initialRecord = try llmSettings.read()
        precondition(initialRecord.isEmpty)

        try llmSettings.write(LLMSettingsRecord(
            url: "http://vault.local:5500",
            model: "modelo-vault",
            contextLimit: "4096"
        ))
        let stored = try llmSettings.read()
        precondition(stored.url == "http://vault.local:5500")
        precondition(stored.model == "modelo-vault")
        precondition(stored.contextLimit == "4096")

        try llmSettings.write(LLMSettingsRecord(
            url: "  http://vault.local:5500  ",
            model: "  ",
            contextLimit: nil
        ))
        let trimmedStored = try llmSettings.read()
        precondition(trimmedStored.url == "http://vault.local:5500")
        precondition(trimmedStored.model == nil)
        precondition(trimmedStored.contextLimit == nil)

        try llmSettings.clear()
        let cleared = try llmSettings.read()
        precondition(cleared.isEmpty)

        let chatTime0 = ClockTimestamp.nowISO8601()
        try repository.appendChatMessage(ChatMessage(
            id: "chat-1",
            itemID: article.id,
            role: .user,
            content: "Sobre o que é o item?",
            createdAt: chatTime0
        ))
        try repository.appendChatMessage(ChatMessage(
            id: "chat-2",
            itemID: article.id,
            role: .assistant,
            content: "Ele trata da Academia de Platão.",
            createdAt: ClockTimestamp.nowISO8601()
        ))
        let chatHistoryArticle = try repository.chatHistory(forItemID: article.id)
        precondition(chatHistoryArticle.count == 2)
        precondition(chatHistoryArticle[0].id == "chat-1")
        precondition(chatHistoryArticle[0].role == .user)
        precondition(chatHistoryArticle[1].role == .assistant)
        let bookmarkChatHistory = try repository.chatHistory(forItemID: bookmark.id)
        precondition(bookmarkChatHistory.isEmpty)

        try repository.clearChatHistory(forItemID: article.id)
        let clearedChatHistory = try repository.chatHistory(forItemID: article.id)
        precondition(clearedChatHistory.isEmpty)

        let chatCascadeItem = try repository.createItem(
            kind: .article,
            sourceURL: nil,
            title: "Cascade chat",
            note: nil,
            bodyText: nil,
            tags: []
        )
        try repository.appendChatMessage(ChatMessage(
            itemID: chatCascadeItem.id,
            role: .user,
            content: "ping"
        ))
        let chatCascadeBefore = try repository.chatHistory(forItemID: chatCascadeItem.id)
        precondition(chatCascadeBefore.count == 1)
        try repository.deleteItems(ids: [chatCascadeItem.id])
        let chatCascadeAfter = try repository.chatHistory(forItemID: chatCascadeItem.id)
        precondition(chatCascadeAfter.isEmpty)

        let cascadeJobItem = try repository.createItem(
            kind: .article,
            sourceURL: "https://example.com/cascade",
            title: "Cascade job",
            note: nil,
            bodyText: nil,
            tags: []
        )
        try repository.insertJobs([Job(id: "job-cascade", itemID: cascadeJobItem.id, kind: .scrapeArticle)])
        let cascadeJobsBeforeDelete = try repository.jobs(forItemID: cascadeJobItem.id)
        precondition(cascadeJobsBeforeDelete.count == 1)
        try repository.deleteItems(ids: [cascadeJobItem.id])
        let cascadeJobsAfterDelete = try repository.jobs(forItemID: cascadeJobItem.id)
        precondition(cascadeJobsAfterDelete.isEmpty)

        let patchedItem = try repository.patchItem(
            id: item.id,
            patch: ItemPatch(
                title: "Ética socrática",
                note: "Maiêutica com [[\(article.id)|Academia antiga]]",
                bodyText: "Virtude e conhecimento caminham juntos.",
                tags: ["etica", "filosofia"]
            )
        )
        let patchedSearchIDs = try repository.search("maieutica").map(\.id)
        let patchedTagCounts = try repository.tagCounts()
        precondition(patchedItem.title == "Ética socrática")
        precondition(patchedItem.note == "Maiêutica com [[\(article.id)|Academia antiga]]")
        precondition(patchedItem.bodyText == "Virtude e conhecimento caminham juntos.")
        precondition(patchedItem.tags == ["etica", "filosofia"])
        precondition(patchedSearchIDs == [item.id])
        precondition(patchedTagCounts == [
            TagCount(name: "dev", count: 1),
            TagCount(name: "etica", count: 1),
            TagCount(name: "filosofia", count: 2),
            TagCount(name: "platao", count: 1),
        ])
        let itemLinkedItems = try repository.linkedItems(from: item.id)
        let articleBacklinks = try repository.backlinks(to: article.id)
        precondition(itemLinkedItems == [
            ItemSummary(id: article.id, title: article.title, kind: .article, capturedAt: article.capturedAt),
        ])
        precondition(articleBacklinks == [
            ItemSummary(id: item.id, title: patchedItem.title, kind: .note, capturedAt: item.capturedAt),
        ])

        let renamedArticle = try repository.patchItem(
            id: article.id,
            patch: ItemPatch(title: "Academia atualizada")
        )
        let renamedLinkedItems = try repository.linkedItems(from: item.id)
        precondition(renamedLinkedItems == [
            ItemSummary(id: article.id, title: renamedArticle.title, kind: .article, capturedAt: article.capturedAt),
        ])

        try repository.deleteItems(ids: [bookmark.id])
        do {
            _ = try repository.item(id: bookmark.id)
            preconditionFailure("Deleted item was still readable.")
        } catch DataError.itemNotFound {
            // Expected: deleted items are not readable.
        }
        let postDeleteCounts = try repository.itemCountsByKind()
        let postDeleteTagCounts = try repository.tagCounts()
        let postDeleteFolders = try repository.listFolders()
        let postDeleteTotalItemCount = try repository.totalItemCount()
        precondition(postDeleteTotalItemCount == 2)
        precondition(postDeleteCounts[.bookmark] == 0)
        precondition(postDeleteTagCounts == [
            TagCount(name: "etica", count: 1),
            TagCount(name: "filosofia", count: 2),
            TagCount(name: "platao", count: 1),
        ])
        precondition(postDeleteFolders == [Folder(id: folder.id, name: "Estudos antigos", itemCount: 2, createdAt: folder.createdAt)])

        try repository.deleteItems(ids: [article.id])
        let linksAfterTargetDelete = try repository.linkedItems(from: item.id)
        let backlinksAfterTargetDelete = try repository.backlinks(to: article.id)
        precondition(linksAfterTargetDelete.isEmpty)
        precondition(backlinksAfterTargetDelete.isEmpty)
        try repository.deleteFolder(id: folder.id)
        let foldersAfterDelete = try repository.listFolders()
        precondition(foldersAfterDelete.isEmpty)

        let firstAssetKey = try database.loadOrCreateAssetKeyData()
        let secondAssetKey = try database.loadOrCreateAssetKeyData()
        precondition(firstAssetKey.count == 32)
        precondition(secondAssetKey == firstAssetKey)

        let store = try EncryptedAssetStore(
            rootDirectory: appPaths.assetsDirectory,
            cacheDirectory: appPaths.temporaryCacheDirectory,
            keyData: firstAssetKey
        )
        let plaintext = Data("asset sensível do vault".utf8)
        let storedAsset = try store.write(
            data: plaintext,
            itemID: item.id,
            role: .original,
            originalFilename: "vault.txt",
            mimeType: "text/plain"
        )
        let ciphertext = try Data(contentsOf: storedAsset.absoluteURL)
        let restoredAsset = try store.read(record: storedAsset.record)
        precondition(ciphertext != plaintext)
        precondition(restoredAsset == plaintext)
        try repository.insertAsset(storedAsset.record)
        let itemAssets = try repository.assets(forItemID: item.id)
        precondition(itemAssets == [storedAsset.record])
        let batchAssets = try repository.assets(forItemIDs: [item.id, article.id])
        precondition(batchAssets == [storedAsset.record])

        let rollbackAsset = try store.write(
            data: Data("rollback asset".utf8),
            itemID: item.id,
            role: .subtitle,
            originalFilename: "rollback.vtt",
            mimeType: "text/vtt"
        )
        try repository.insertAsset(rollbackAsset.record)
        let assetsWithRollback = try repository.assets(forItemID: item.id)
        precondition(assetsWithRollback.contains(rollbackAsset.record))
        try repository.deleteAssets(ids: [rollbackAsset.record.id])
        let assetsAfterRollbackRowDelete = try repository.assets(forItemID: item.id)
        precondition(!assetsAfterRollbackRowDelete.contains(rollbackAsset.record))
        precondition(FileManager.default.fileExists(atPath: rollbackAsset.absoluteURL.path))
        try store.remove(record: rollbackAsset.record)

        let batchDeleteA = try repository.createItem(
            kind: .note,
            title: "Excluir em lote A",
            note: nil,
            bodyText: nil,
            tags: ["batch"]
        )
        let batchDeleteB = try repository.createItem(
            kind: .note,
            title: "Excluir em lote B",
            note: nil,
            bodyText: nil,
            tags: ["batch"]
        )
        let batchStoredAsset = try store.write(
            data: Data("batch asset".utf8),
            itemID: batchDeleteA.id,
            role: .original,
            originalFilename: "batch.txt",
            mimeType: "text/plain"
        )
        try repository.insertAsset(batchStoredAsset.record)
        let assetsBeforeBatchDelete = try repository.assets(forItemIDs: [batchDeleteA.id, batchDeleteB.id])
        precondition(assetsBeforeBatchDelete == [batchStoredAsset.record])
        try repository.deleteItems(ids: [batchDeleteA.id, batchDeleteB.id])
        for asset in assetsBeforeBatchDelete {
            try store.remove(record: asset)
        }
        let assetsAfterBatchDelete = try repository.assets(forItemIDs: [batchDeleteA.id, batchDeleteB.id])
        precondition(assetsAfterBatchDelete.isEmpty)
        precondition(!FileManager.default.fileExists(atPath: batchStoredAsset.absoluteURL.path))

        let decryptedTemp = try store.decryptToTemporaryFile(record: storedAsset.record)
        let decryptedTempData = try Data(contentsOf: decryptedTemp)
        precondition(decryptedTempData == plaintext)
        try store.clearTemporaryCache()
        precondition(!FileManager.default.fileExists(atPath: decryptedTemp.path))

        let tools = DependencyDoctor.productionRequirements.map(\.executable)
        precondition(tools == ["sqlcipher", "ffmpeg", "yt-dlp", "gallery-dl", "trafilatura"])

        do {
            try database.changePassphrase(to: "")
            preconditionFailure("Empty passphrase was accepted.")
        } catch DataError.emptyPassphrase {
            // Expected: empty vault passphrases are not valid.
        }

        let verifier = try NativeDatabase(
            appPaths: appPaths,
            passphrase: "test",
            requireSQLCipher: true
        )
        try verifier.close()

        try database.changePassphrase(to: "changed")
        let rekeyedAssetKey = try database.loadOrCreateAssetKeyData()
        precondition(rekeyedAssetKey == firstAssetKey)
        try database.close()

        do {
            let oldPassphraseDatabase = try NativeDatabase(
                appPaths: appPaths,
                passphrase: "test",
                requireSQLCipher: true
            )
            try oldPassphraseDatabase.close()
            preconditionFailure("Old passphrase opened the vault after rekey.")
        } catch {
            // Expected: SQLCipher must reject the old passphrase after rekey.
        }

        let reopened = try NativeDatabase(
            appPaths: appPaths,
            passphrase: "changed",
            requireSQLCipher: true
        )
        let reopenedAssetKey = try reopened.loadOrCreateAssetKeyData()
        precondition(reopenedAssetKey == firstAssetKey)
        let reopenedStore = try EncryptedAssetStore(
            rootDirectory: appPaths.assetsDirectory,
            cacheDirectory: appPaths.temporaryCacheDirectory,
            keyData: reopenedAssetKey
        )
        let reopenedAsset = try reopenedStore.read(record: storedAsset.record)
        precondition(reopenedAsset == plaintext)
        try reopened.close()

        let sqliteRead = Process()
        sqliteRead.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        sqliteRead.arguments = [
            root.appendingPathComponent("Hypomnemata.sqlite").path,
            "select count(*) from items;",
        ]
        sqliteRead.standardOutput = Pipe()
        sqliteRead.standardError = Pipe()
        try sqliteRead.run()
        sqliteRead.waitUntilExit()
        precondition(sqliteRead.terminationStatus != 0)
    }

    private static func checkMedia() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hypomnemata-media-checks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try EncryptedAssetStore(
            rootDirectory: root.appendingPathComponent("assets", isDirectory: true),
            cacheDirectory: root.appendingPathComponent("cache", isDirectory: true),
            keyData: EncryptedAssetStore.generateKeyData()
        )

        let plaintext = Data("conteúdo sensível".utf8)
        let stored = try store.write(
            data: plaintext,
            itemID: "item-1",
            role: .original,
            originalFilename: "nota.txt",
            mimeType: "text/plain"
        )

        let restored = try store.read(record: stored.record)
        let ciphertext = try Data(contentsOf: stored.absoluteURL)
        precondition(restored == plaintext)
        precondition(ciphertext != plaintext)

        let temp = try store.decryptToTemporaryFile(record: stored.record)
        let tempData = try Data(contentsOf: temp)
        precondition(tempData == plaintext)
        try store.clearTemporaryCache()
        precondition(!FileManager.default.fileExists(atPath: temp.path))

        let recreated = root.appendingPathComponent("cache", isDirectory: true)
        precondition(FileManager.default.fileExists(atPath: recreated.path))

        let missingCache = root.appendingPathComponent("missing-cache", isDirectory: true)
        try TemporaryCacheCleaner().clear(at: missingCache)
        precondition(FileManager.default.fileExists(atPath: missingCache.path))

        let imageURL = root.appendingPathComponent("thumbnail-source.png")
        try makePNG(width: 320, height: 180).write(to: imageURL)
        let thumbnailData = try NativeThumbnailGenerator(maxPixelSize: 128)
            .makeJPEGThumbnailData(for: imageURL, mimeType: "image/png")
        precondition(thumbnailData.count > 0)
        let thumbnailImage = NSImage(data: thumbnailData)
        precondition(thumbnailImage != nil)

        let unsupportedURL = root.appendingPathComponent("unsupported.txt")
        try Data("sem thumbnail".utf8).write(to: unsupportedURL)
        do {
            _ = try NativeThumbnailGenerator().makeJPEGThumbnailData(for: unsupportedURL, mimeType: "text/plain")
            preconditionFailure("Text file generated a thumbnail.")
        } catch ThumbnailGenerationError.unsupportedAsset {
            // Expected: only images, PDFs and videos have native thumbnails here.
        }

        let pdfURL = root.appendingPathComponent("ocr-source.pdf")
        try makePDF(text: "Texto OCR nativo verificavel").write(to: pdfURL)
        let pdfText = try NativeOCRExtractor().extractText(from: pdfURL, mimeType: "application/pdf")
        precondition(pdfText.localizedCaseInsensitiveContains("Texto OCR nativo"))

        do {
            _ = try NativeOCRExtractor().extractText(from: unsupportedURL, mimeType: "text/plain")
            preconditionFailure("Text file was accepted for OCR.")
        } catch NativeOCRError.unsupportedAsset {
            // Expected: OCR is limited to images and PDFs in the native app.
        }

        try store.remove(record: stored.record)
        precondition(!FileManager.default.fileExists(atPath: stored.absoluteURL.path))
        do {
            _ = try store.read(record: stored.record)
            preconditionFailure("Removed asset was still readable.")
        } catch MediaError.assetNotFound {
            // Expected: removed encrypted assets are no longer readable.
        }
    }

    private static func makePNG(width: Int, height: Int) throws -> Data {
        let image = NSImage(size: CGSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor.white.setFill()
        NSRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2).fill()
        image.unlockFocus()
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw ThumbnailGenerationError.encodingFailed
        }
        return data
    }

    private static func makePDF(text: String) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            throw ThumbnailGenerationError.encodingFailed
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ThumbnailGenerationError.encodingFailed
        }

        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (text as NSString).draw(
            at: CGPoint(x: 72, y: 680),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 24),
                .foregroundColor: NSColor.black,
            ]
        )
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private static func checkPerformance() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hypomnemata-performance-checks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try NativeDatabase(
            appPaths: AppPaths(rootDirectory: root),
            passphrase: "performance",
            requireSQLCipher: true
        )
        defer { try? database.close() }

        let repository = SQLiteItemRepository(database: database)
        let now = ClockTimestamp.nowISO8601()
        var insertedIDs: [String] = []
        insertedIDs.reserveCapacity(10_000)

        try database.writer.write { db in
            for index in 0..<10_000 {
                let id = UUIDV7.generateString()
                insertedIDs.append(id)
                let kind: ItemKind = index.isMultiple(of: 2) ? .note : .article
                try db.execute(
                    sql: """
                        INSERT INTO items(
                            id, kind, source_url, title, note, body_text, summary, meta_json,
                            captured_at, created_at, updated_at
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        id,
                        kind.rawValue,
                        index.isMultiple(of: 2) ? nil : "https://example.com/perf-\(index)",
                        "Item perf \(index)",
                        "nota perf \(index)",
                        "corpo perf token\(index)",
                        index.isMultiple(of: 5) ? "resumo perf \(index)" : nil,
                        nil,
                        now,
                        now,
                        now,
                    ]
                )
            }
        }

        let listStart = Date()
        let listed = try repository.listItems(filter: ItemListFilter(limit: 200))
        let listElapsed = Date().timeIntervalSince(listStart)
        precondition(listed.count == 200)
        precondition(listElapsed < 2.0)

        let searchStart = Date()
        let found = try repository.search("token9999", filter: ItemListFilter(limit: 20))
        let searchElapsed = Date().timeIntervalSince(searchStart)
        precondition(found.count == 1)
        precondition(found[0].title == "Item perf 9999")
        precondition(searchElapsed < 2.0)

        let deleteIDs = Array(insertedIDs.prefix(500))
        let deleteStart = Date()
        try repository.deleteItems(ids: deleteIDs)
        let deleteElapsed = Date().timeIntervalSince(deleteStart)
        let remainingCount = try repository.totalItemCount()
        precondition(remainingCount == 9_500)
        precondition(deleteElapsed < 5.0)
    }
}

private final class FakeLLMClient: LLMClient, @unchecked Sendable {
    private let response: String
    private(set) var lastMessages: [LLMMessage]?

    init(response: String) {
        self.response = response
    }

    func complete(messages: [LLMMessage], temperature: Double) async throws -> String {
        lastMessages = messages
        return response
    }

    func streamChat(messages: [LLMMessage], temperature: Double) -> AsyncThrowingStream<String, Error> {
        lastMessages = messages
        return AsyncThrowingStream { continuation in
            continuation.yield(response)
            continuation.finish()
        }
    }
}

private struct FakeArticleScraper: ArticleScraper {
    var result: ArticleScrapeResult
    var expectedURL: String

    func scrape(url: String) async throws -> ArticleScrapeResult {
        precondition(url == expectedURL)
        return result
    }
}

private struct FakePageRenderer: JSPageRenderer {
    var html: String

    func renderHTML(url: String) async throws -> String {
        html
    }
}

private struct FakeMediaDownloader: MediaDownloader {
    var result: MediaDownloadResult
    var expectedURL: String

    func download(url: String) async throws -> MediaDownloadResult {
        precondition(url == expectedURL)
        return result
    }
}

private struct FakeRemoteThumbnailFetcher: RemoteThumbnailFetcher {
    var result: RemoteThumbnailResult
    var expectedURL: String

    func fetchThumbnail(url: String) async throws -> RemoteThumbnailResult {
        precondition(url == expectedURL)
        return result
    }
}
