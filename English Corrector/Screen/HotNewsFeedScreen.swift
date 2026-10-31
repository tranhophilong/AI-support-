//
//  HotNewsFeedScreen.swift
//  English Corrector
//

import SwiftUI

struct HotNewsFeedScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: NewsCategory = .top
    @State private var articles: [NewsArticleItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var searchText: String = ""
    @State private var selectedArticleForReading: NewsArticleItem?

    var filteredArticles: [NewsArticleItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return articles
        }
        let query = searchText.lowercased()
        return articles.filter {
            $0.title.lowercased().contains(query) ||
            $0.description.lowercased().contains(query) ||
            $0.source.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryTabsHeader

                if isLoading && articles.isEmpty {
                    loadingView
                } else if let error = errorMessage, articles.isEmpty {
                    errorStateView(error)
                } else if filteredArticles.isEmpty {
                    emptyStateView
                } else {
                    articlesListView
                }
            }
            .background(AppTheme.Neutral.n50.ignoresSafeArea())
            .navigationTitle("Tin tức tiếng Anh")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Tìm kiếm tin tức..."
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await loadArticles(forceRefresh: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(AppTheme.Primary.p500)
                    }
                }
            }
            .task(id: selectedCategory) {
                await loadArticles(forceRefresh: false)
            }
            .fullScreenCover(item: $selectedArticleForReading) { article in
                NewsArticleReaderScreen(article: article)
            }
        }
    }

    // MARK: - Category Tabs Header

    private var categoryTabsHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NewsCategory.allCases) { category in
                    let isSelected = (selectedCategory == category)

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.iconName)
                                .font(.caption2)

                            Text(category.displayName)
                                .font(.subheadline.bold())
                        }
                        .foregroundStyle(isSelected ? Color.white : AppTheme.Neutral.n700)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isSelected
                            ? AppTheme.Primary.p500
                            : Color.white
                        )
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isSelected
                                    ? AppTheme.Primary.p500
                                    : AppTheme.Neutral.n200,
                                    lineWidth: 0.5
                                )
                        }
                        .shadow(
                            color: isSelected
                            ? AppTheme.Primary.p500.opacity(0.25)
                            : Color.clear,
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Articles List View

    private var articlesListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredArticles) { article in
                    articleCardRow(article)
                        .onTapGesture {
                            selectedArticleForReading = article
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await loadArticles(forceRefresh: true)
        }
    }

    private func articleCardRow(_ article: NewsArticleItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Source & Time
            HStack(spacing: 6) {
                Text(article.source)
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.Primary.p700)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppTheme.Primary.p50)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(AppTheme.Primary.p300.opacity(0.5), lineWidth: 0.5)
                    }

                Text("•")
                    .foregroundStyle(AppTheme.Neutral.n400)

                Text(article.timeAgoDisplay)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Neutral.n500)

                Spacer()

                Image(systemName: "book.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Accent.a600)
                Text("Reader Mode")
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.Accent.a600)
            }

            HStack(alignment: .top, spacing: 12) {
                // Headline & snippet
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.Neutral.n900)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    if !article.description.isEmpty {
                        Text(article.description)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)

                // Thumbnail
                if let imgURL = article.imageURL, let url = URL(string: imgURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 88, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        default:
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppTheme.Neutral.n100)
                                .frame(width: 88, height: 72)
                                .overlay {
                                    Image(systemName: "newspaper")
                                        .foregroundStyle(AppTheme.Neutral.n400)
                                }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.Neutral.n200, lineWidth: 0.5)
        }
        .shadow(color: AppTheme.Neutral.n900.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    // MARK: - States: Loading, Error, Empty

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.1)

            Text("Đang tải tin tức tiếng Anh mới nhất...")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Neutral.n500)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorStateView(_ error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.Neutral.n400)

            Text("Không thể tải tin tức")
                .font(.headline.bold())
                .foregroundStyle(AppTheme.Neutral.n900)

            Text(error)
                .font(.caption)
                .foregroundStyle(AppTheme.Neutral.n500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task {
                    await loadArticles(forceRefresh: true)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Thử lại")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(AppTheme.Primary.p500)
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.Neutral.n400)

            Text("Không tìm thấy bài báo nào")
                .font(.headline)
                .foregroundStyle(AppTheme.Neutral.n700)

            Text("Hãy thử tìm kiếm với từ khóa khác hoặc chuyển sang danh mục khác.")
                .font(.caption)
                .foregroundStyle(AppTheme.Neutral.n500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Fetching

    private func loadArticles(forceRefresh: Bool) async {
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await EnglishNewsService.shared.fetchArticles(
                for: selectedCategory,
                forceRefresh: forceRefresh
            )
            await MainActor.run {
                self.articles = fetched
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Kiểm tra kết nối mạng và thử lại sau."
                self.isLoading = false
            }
        }
    }
}
