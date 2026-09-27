//
//  ListConversationScreen.swift
//  English Corrector
//
//  Created by Long Tran on 16/5/26.
//

import SwiftUI
import SwiftData

struct ListConversationScreen: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \ConversationModel.createdAt, order: .reverse) private var conversations: [ConversationModel]

    @AppStorage("hasSeenWidgetOnboarding") private var hasSeenWidgetOnboarding = false

    @State private var path = NavigationPath()
    @State private var showWidgetOnboarding = false
    @State private var showNotedAIScreen = false

    var body: some View {

        NavigationStack(path: $path) {

            ZStack {
                AppTheme.Surface.appBackground
                    .ignoresSafeArea()

                // EMPTY STATE
                if conversations.isEmpty {

                    VStack(spacing: 18) {

                        Image(systemName: "message.badge.plus")
                            .font(.system(size: 64))
                            .foregroundStyle(AppTheme.Primary.p500)
                            .frame(width: 104, height: 104)
                            .background(AppTheme.Primary.p100)
                            .clipShape(Circle())

                        Text("No Conversations Yet")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.Neutral.n900)

                        Text("Start practicing your English with AI")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Neutral.n500)

                        Button {

                            createConversation()

                        } label: {

                            HStack(spacing: 10) {

                                Image(systemName: "plus")

                                Text("Create Conversation")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(AppTheme.Primary.p500)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .shadow(
                                color: AppTheme.Primary.p500.opacity(0.22),
                                radius: 14,
                                x: 0,
                                y: 8
                            )
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .padding(.top, 100)
                    .padding()

                } else {

                    // LIST STATE
                    ScrollView {

                        LazyVStack(spacing: 14) {

                            ForEach(conversations) { conversation in

                                NavigationLink(value: conversation) {

                                    ConversationCard(
                                        conversation: conversation
                                    )
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        deleteConversation(conversation)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteConversation(conversation)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Conversations")
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {

                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        NotedAIScreen()
                    } label: {
                        Image(systemName: "note.text")
                            .foregroundStyle(AppTheme.Accent.a600)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {

                    Button {

                        createConversation()

                    } label: {

                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(AppTheme.Primary.p700)
                    }
                }
            }
            .navigationDestination(for: ConversationModel.self) { conversation in

                ChatScreen(conversation: conversation)
            }
            .navigationDestination(isPresented: $showNotedAIScreen) {
                NotedAIScreen()
            }
            .sheet(isPresented: $showWidgetOnboarding) {
                WidgetOnboardingSheet(
                    onOpenNotedAI: {
                        hasSeenWidgetOnboarding = true
                        showWidgetOnboarding = false
                        showNotedAIScreen = true
                    },
                    onDismiss: {
                        hasSeenWidgetOnboarding = true
                        showWidgetOnboarding = false
                    }
                )
                .onDisappear {
                    hasSeenWidgetOnboarding = true
                }
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                print("DEBUG: Conversations loaded: \(conversations.count)")
                showWidgetOnboardingIfNeeded()
            }
        }
    }

    // MARK: - Create Conversation

    @MainActor
    private func createConversation() {

        let conversation = ConversationModel(
            title: "Daily Life English",
            conversationDescription: """
 Help me practice casual English for daily conversations.
 Fix grammar mistakes and rewrite my sentences like a native speaker.
 Keep responses simple and friendly.
 """
        )

        // insert
        context.insert(conversation)

        do {
            try context.save()
            print("DEBUG: Successfully created and saved conversation.")
        } catch {
            print("DEBUG: Failed to save conversation: \(error)")
        }

        // navigate
        path.append(conversation)
    }

    private func deleteConversation(_ conversation: ConversationModel) {
        context.delete(conversation)

        do {
            try context.save()
            print("DEBUG: Successfully deleted conversation.")
        } catch {
            print("DEBUG: Failed to delete conversation: \(error)")
        }
    }

    private func showWidgetOnboardingIfNeeded() {
        guard !hasSeenWidgetOnboarding else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showWidgetOnboarding = true
        }
    }
}

private struct WidgetOnboardingSheet: View {
    let onOpenNotedAI: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.title2)
                    .foregroundStyle(AppTheme.Accent.a600)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.Accent.a100)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Noted AI Widget")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Neutral.n900)

                    Text("Review saved notes from your iPhone Home Screen.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                WidgetOnboardingStep(
                    icon: "note.text",
                    title: "Save notes",
                    message: "Open Noted AI and sync your saved notes to the widget."
                )

                WidgetOnboardingStep(
                    icon: "hand.tap",
                    title: "Add manually",
                    message: "On the Home Screen, touch and hold, tap +, then choose Noted AI."
                )

                WidgetOnboardingStep(
                    icon: "arrow.clockwise",
                    title: "Keep it updated",
                    message: "Use the widget sync button any time you want to refresh notes."
                )
            }

            Spacer(minLength: 0)

            Button {
                onOpenNotedAI()
            } label: {
                Label("Open Noted AI", systemImage: "note.text")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.Primary.p500)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button("Later") {
                onDismiss()
            }
            .font(.subheadline.bold())
            .foregroundStyle(AppTheme.Neutral.n500)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding(22)
        .background(AppTheme.Surface.appBackground)
    }
}

private struct WidgetOnboardingStep: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppTheme.Primary.p500)
                .frame(width: 28, height: 28)
                .background(AppTheme.Primary.p50)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.Neutral.n900)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
// MARK: - Conversation Card

struct ConversationCard: View {

    let conversation: ConversationModel

    var body: some View {

        VStack(alignment: .leading, spacing: 10) {

            HStack {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Secondary.s600)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.Secondary.s100)
                    .clipShape(Circle())

                Text(conversation.title.isEmpty ? "New Chat" : conversation.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.Neutral.n900)

                Spacer()

                Text(conversation.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Neutral.n500)
            }

            if !conversation.conversationDescription.isEmpty {

                Text(conversation.conversationDescription)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Neutral.n700)
                    .lineLimit(2)
            }

            Text(conversation.messages.sorted(by: { $0.createdAt < $1.createdAt }).last?.text ?? "No messages yet")
                .font(.footnote)
                .foregroundStyle(AppTheme.Neutral.n500)
                .lineLimit(1)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Surface.card)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.Surface.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(
            color: AppTheme.Shadow.card,
            radius: 12,
            x: 0,
            y: 6
        )
    }
}


#Preview {
    ListConversationScreen()
        .modelContainer(for: [ConversationModel.self], inMemory: true)
}
