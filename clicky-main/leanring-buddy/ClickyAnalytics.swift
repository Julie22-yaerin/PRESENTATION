//
//  ClickyAnalytics.swift
//  leanring-buddy
//
//  Centralized PostHog analytics wrapper. All event names and properties
//  are defined here so instrumentation is consistent and easy to audit.
//

import Foundation
import PostHog

enum ClickyAnalytics {

    // MARK: - Setup

    static func configure() {
        let config = PostHogConfig(
            apiKey: "phc_xcQPygmhTMzzYh8wNW92CCwoXmnzqyChAixh8zgpqC3C",
            host: "https://us.i.posthog.com"
        )
        PostHogSDK.shared.setup(config)
    }

    // MARK: - App Lifecycle

    /// Fired once on every app launch in applicationDidFinishLaunching.
    static func trackAppOpened() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        PostHogSDK.shared.capture("app_opened", properties: [
            "app_version": version
        ])
    }

    // MARK: - Onboarding

    /// User clicked the Start button to begin onboarding for the first time.
    static func trackOnboardingStarted() {
        PostHogSDK.shared.capture("onboarding_started")
    }

    /// User clicked "Watch Onboarding Again" from the panel footer.
    static func trackOnboardingReplayed() {
        PostHogSDK.shared.capture("onboarding_replayed")
    }

    /// The onboarding video finished playing to the end.
    static func trackOnboardingVideoCompleted() {
        PostHogSDK.shared.capture("onboarding_video_completed")
    }

    /// The 40s onboarding demo interaction where Clicky points at something.
    static func trackOnboardingDemoTriggered() {
        PostHogSDK.shared.capture("onboarding_demo_triggered")
    }

    // MARK: - Permissions

    /// All three permissions (accessibility, screen recording, mic) are granted.
    static func trackAllPermissionsGranted() {
        PostHogSDK.shared.capture("all_permissions_granted")
    }

    /// A single permission was granted. Called when polling detects a change.
    static func trackPermissionGranted(permission: String) {
        PostHogSDK.shared.capture("permission_granted", properties: [
            "permission": permission
        ])
    }

    // MARK: - Voice Interaction

    /// User pressed the push-to-talk shortcut (control+option) to start talking.
    static func trackPushToTalkStarted() {
        PostHogSDK.shared.capture("push_to_talk_started")
    }

    /// User released the shortcut — transcript is being finalized.
    static func trackPushToTalkReleased() {
        PostHogSDK.shared.capture("push_to_talk_released")
    }

    /// Transcription completed and the user's message is being sent to the AI.
    static func trackUserMessageSent(transcript: String) {
        PostHogSDK.shared.capture("user_message_sent", properties: [
            "transcript": transcript,
            "character_count": transcript.count
        ])
    }

    /// Claude responded and the response is being spoken via TTS.
    static func trackAIResponseReceived(response: String) {
        PostHogSDK.shared.capture("ai_response_received", properties: [
            "response": response,
            "character_count": response.count
        ])
    }

    /// Claude's response included a [POINT:x,y:label] coordinate tag,
    /// so the buddy is flying to point at a UI element.
    static func trackElementPointed(elementLabel: String?) {
        PostHogSDK.shared.capture("element_pointed", properties: [
            "element_label": elementLabel ?? "unknown"
        ])
    }

    // MARK: - Lyceum Coaching

    /// A practice run started (mic open, slide watcher running).
    static func trackCoachSessionStarted(mode: String) {
        PostHogSDK.shared.capture("lyceum_session_started", properties: [
            "mode": mode
        ])
    }

    /// A run was graded and the report is on screen.
    static func trackCoachSessionCompleted(mode: String, durationSeconds: TimeInterval, slideCount: Int, degraded: Bool) {
        PostHogSDK.shared.capture("lyceum_session_completed", properties: [
            "mode": mode,
            "duration_seconds": Int(durationSeconds),
            "slide_count": slideCount,
            "report_degraded": degraded
        ])
    }

    /// A run could not be graded (no speech, API failure, permissions).
    static func trackCoachSessionFailed(message: String) {
        PostHogSDK.shared.capture("lyceum_session_failed", properties: [
            "error": message
        ])
    }

    /// The user exported a report to Markdown or JSON.
    static func trackCoachReportExported(format: String) {
        PostHogSDK.shared.capture("lyceum_report_exported", properties: [
            "format": format
        ])
    }

    // MARK: - The Lyceum gate and audience panel

    /// A practice run was refused because the app in front was not a slide tool.
    static func trackLyceumGateBlocked(reason: String) {
        PostHogSDK.shared.capture("lyceum_gate_blocked", properties: [
            "reason": reason
        ])
    }

    /// A run stopped by itself on a farewell slide or heard closing words.
    static func trackLyceumRunAutoEnded(kind: String) {
        PostHogSDK.shared.capture("lyceum_run_auto_ended", properties: [
            "kind": kind
        ])
    }

    /// The panel was convened with N questions.
    static func trackLyceumPanelConvened(questionCount: Int) {
        PostHogSDK.shared.capture("lyceum_panel_convened", properties: [
            "question_count": questionCount
        ])
    }

    /// A question was answered out loud.
    static func trackLyceumAnswerGiven(questionKind: String) {
        PostHogSDK.shared.capture("lyceum_answer_given", properties: [
            "question_kind": questionKind
        ])
    }

    /// How the talk held up under questioning, 0-10.
    static func trackLyceumDefenseScored(value: Int) {
        PostHogSDK.shared.capture("lyceum_defense_scored", properties: [
            "value": value
        ])
    }

    /// The dashboard window was opened. It says nothing about what was in it.
    static func trackLyceumDashboardOpened() {
        PostHogSDK.shared.capture("lyceum_dashboard_opened", properties: [
            "window": "practice_dashboard"
        ])
    }

    /// A delivery dial moved. Only the two switches travel, never a number measured
    /// from a student's voice or face.
    static func trackLyceumDeliverySettings(measuresDelivery: Bool, cameraStills: Bool) {
        PostHogSDK.shared.capture("lyceum_delivery_settings", properties: [
            "measures_delivery": measuresDelivery,
            "camera_stills": cameraStills
        ])
    }

    // MARK: - Errors

    /// An error occurred during the AI response pipeline.
    static func trackResponseError(error: String) {
        PostHogSDK.shared.capture("response_error", properties: [
            "error": error
        ])
    }

    /// An error occurred during TTS playback.
    static func trackTTSError(error: String) {
        PostHogSDK.shared.capture("tts_error", properties: [
            "error": error
        ])
    }
}
