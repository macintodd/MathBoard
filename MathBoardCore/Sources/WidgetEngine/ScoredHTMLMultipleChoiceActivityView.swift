//
//  ScoredHTMLMultipleChoiceActivityView.swift
//  WidgetEngine
//
//  WebView-backed multiple-choice renderer that uses the same activity JSON and
//  runtime state as the native scorer.
//

import SwiftUI
import WebKit

struct ScoredHTMLMultipleChoiceActivityView: View {
    let document: ActivityWidgetDocument
    @Binding var runtimeState: WidgetMultipleChoiceRuntimeState
    var scoreSheet: WidgetActivityScoreSheet?
    var onEditWidget: (() -> Void)?
    var gearConfiguration: WidgetGearConfiguration?
    let theme: WidgetActivityVisualTheme

    @State private var showsScoreSheet = false

    private var scoreRecord: WidgetActivityScoreRecord {
        runtimeState.scoreRecord(for: document)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.black.opacity(0.10))
                        .frame(height: 1)
                }

            ScoredHTMLMultipleChoiceWebView(
                document: document,
                runtimeState: $runtimeState,
                onSubmitWidget: gearConfiguration?.onSubmitWidget
            )
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1.5)
        )
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Text("Score \(scoreRecord.score)/\(scoreRecord.pointsPossible) • Attempts \(scoreRecord.attempts)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Button {
                showsScoreSheet.toggle()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
            .accessibilityLabel("Widget settings")
            .popover(isPresented: $showsScoreSheet, arrowEdge: .trailing) {
                htmlWidgetSettingsPopover
            }
        }
    }

    private var htmlWidgetSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Widget")
                .font(.headline.weight(.semibold))
            Button {
                resetWidget()
                showsScoreSheet = false
            } label: {
                Label("Reset Widget", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            if let onEditWidget {
                Button {
                    showsScoreSheet = false
                    onEditWidget()
                } label: {
                    Label("Edit Widget", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
    }

    private func resetWidget() {
        let submittedFlow = runtimeState.flow
        runtimeState = WidgetMultipleChoiceRuntimeState.initial(for: document)
        runtimeState.flow = WidgetActivityAttemptFlowState(
            hasSubmittedScore: submittedFlow?.hasSubmittedScore ?? false,
            submittedRecord: submittedFlow?.submittedRecord
        )
    }
}

@MainActor
private struct ScoredHTMLMultipleChoiceWebView {
    let document: ActivityWidgetDocument
    @Binding var runtimeState: WidgetMultipleChoiceRuntimeState
    var onSubmitWidget: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(runtimeState: $runtimeState, onSubmitWidget: onSubmitWidget)
    }

    fileprivate func makeWebView(coordinator: Coordinator) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(coordinator, name: "mathBoardScoredWidgetState")
        controller.add(coordinator, name: "mathBoardScoredWidgetSubmit")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        #elseif os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        coordinator.isLoaded = false
        webView.loadHTMLString(Self.htmlSource, baseURL: nil)
        coordinator.lastPayloadJSON = nil
        return webView
    }

    fileprivate func updateWebView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.runtimeState = $runtimeState
        coordinator.onSubmitWidget = onSubmitWidget
        guard let payloadJSON = Self.payloadJSON(
            document: document,
            runtimeState: runtimeState,
            canSubmitToTeacher: onSubmitWidget != nil
        ),
              payloadJSON != coordinator.lastPayloadJSON else {
            return
        }
        coordinator.lastPayloadJSON = payloadJSON
        coordinator.pendingPayloadJSON = payloadJSON
        guard coordinator.isLoaded else { return }
        Self.applyPayloadJSON(payloadJSON, to: webView, coordinator: coordinator)
    }

    fileprivate static func dismantle(_ webView: WKWebView) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mathBoardScoredWidgetState")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mathBoardScoredWidgetSubmit")
        webView.navigationDelegate = nil
    }

    fileprivate static func applyPayloadJSON(_ payloadJSON: String, to webView: WKWebView, coordinator: Coordinator) {
        let script = "window.MathBoardScoredWidget && window.MathBoardScoredWidget.applyPayload(\(payloadJSON));"
        webView.evaluateJavaScript(script) { _, _ in
            if coordinator.pendingPayloadJSON == payloadJSON {
                coordinator.pendingPayloadJSON = nil
            }
        }
    }

    private static func payloadJSON(
        document: ActivityWidgetDocument,
        runtimeState: WidgetMultipleChoiceRuntimeState,
        canSubmitToTeacher: Bool
    ) -> String? {
        struct Payload: Encodable {
            let document: ActivityWidgetDocument
            let runtimeState: WidgetMultipleChoiceRuntimeState
            let canSubmitToTeacher: Bool
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(Payload(
            document: document,
            runtimeState: runtimeState,
            canSubmitToTeacher: canSubmitToTeacher
        )) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var runtimeState: Binding<WidgetMultipleChoiceRuntimeState>
        var onSubmitWidget: (() -> Void)?
        var lastPayloadJSON: String?
        var pendingPayloadJSON: String?
        var isLoaded = false

        init(runtimeState: Binding<WidgetMultipleChoiceRuntimeState>, onSubmitWidget: (() -> Void)?) {
            self.runtimeState = runtimeState
            self.onSubmitWidget = onSubmitWidget
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "mathBoardScoredWidgetSubmit" {
                DispatchQueue.main.async {
                    self.onSubmitWidget?()
                }
                return
            }

            guard let source = message.body as? String,
                  let data = source.data(using: .utf8),
                  let nextState = try? JSONDecoder().decode(WidgetMultipleChoiceRuntimeState.self, from: data) else {
                return
            }

            DispatchQueue.main.async {
                self.runtimeState.wrappedValue = nextState
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let pendingPayloadJSON {
                ScoredHTMLMultipleChoiceWebView.applyPayloadJSON(pendingPayloadJSON, to: webView, coordinator: self)
            }
        }
    }

    private static let htmlSource = #"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<title>Scored Multiple Choice</title>
<style>
  :root{
    --text:#161616;
    --secondary:#555b63;
    --muted:#7a8088;
    --bg:#fbfaf6;
    --panel:#ffffff;
    --line:#d1d5db;
    --accent:#2563eb;
    --accent-soft:#dbeafe;
    --math:#6B4FBB;
    --correct:#17803f;
    --correct-soft:#dcfce7;
    --incorrect:#b42318;
    --incorrect-soft:#fee2e2;
    --warn:#92400e;
    --warn-soft:#fef3c7;
  }
  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent;}
  html,body{margin:0;width:100%;height:100%;overflow:hidden;background:var(--bg);color:var(--text);
    font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif;}
  body{font-size:20px;}
  button{font:inherit;color:inherit;}
  #app{height:100%;display:flex;flex-direction:column;padding:18px;gap:12px;overflow:auto;}
  .topline{display:flex;align-items:center;gap:12px;flex-wrap:wrap;}
  .pill{font-size:17px;font-weight:800;color:var(--accent);background:var(--accent-soft);border:2px solid rgba(37,99,235,.35);
    border-radius:999px;padding:8px 12px;}
  .meter{height:14px;flex:1 1 180px;min-width:140px;border-radius:999px;background:#e5e7eb;overflow:hidden;border:1px solid var(--line);}
  .meter span{display:block;height:100%;width:0;background:var(--accent);transition:width .2s ease;}
  .card{background:var(--panel);border:2px solid var(--line);border-radius:16px;padding:18px;box-shadow:0 8px 22px rgba(15,23,42,.08);}
  .prompt{font-size:26px;font-weight:800;line-height:1.2;margin-bottom:4px;}
  .expression{display:flex;justify-content:center;align-items:center;min-height:76px;margin-top:12px;padding:16px;
    border-radius:12px;background:#f8fafc;border:2px solid var(--line);font-size:36px;font-weight:850;}
  .choices{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;}
  .choice{min-height:92px;text-align:left;border:3px solid var(--line);border-radius:14px;background:var(--panel);
    padding:16px;display:flex;align-items:center;gap:12px;font-size:23px;font-weight:750;line-height:1.15;}
  .choice:disabled{opacity:1;}
  .choice.selected{border-color:var(--accent);background:var(--accent-soft);}
  .choice.correct{border-color:var(--correct);background:var(--correct-soft);}
  .choice.incorrect{border-color:var(--incorrect);background:var(--incorrect-soft);}
  .badge{flex:0 0 auto;width:36px;height:36px;border-radius:50%;display:grid;place-items:center;background:#eef2ff;
    color:var(--accent);font-size:18px;font-weight:900;}
  .row{display:flex;gap:10px;align-items:center;flex-wrap:wrap;}
  .row button{min-height:48px;border:2px solid var(--line);border-radius:12px;background:#fff;padding:10px 16px;font-weight:850;}
  .row button.primary{background:var(--accent);border-color:var(--accent);color:white;}
  .row button.success{background:var(--correct);border-color:var(--correct);color:white;}
  .row button:disabled{opacity:.45;}
  .row button.icon-btn{min-width:48px;padding:10px 12px;}
  .hidden{display:none!important;}
  .feedback{min-height:52px;border-radius:12px;border:2px solid var(--line);padding:13px 14px;font-size:21px;font-weight:750;}
  .feedback.correct{background:var(--correct-soft);border-color:var(--correct);color:var(--correct);}
  .feedback.incorrect{background:var(--incorrect-soft);border-color:var(--incorrect);color:var(--incorrect);}
  .feedback.warning{background:var(--warn-soft);border-color:var(--warn);color:var(--warn);}
  .math{font-family:"Times New Roman",Times,serif;font-style:italic;white-space:nowrap;color:var(--math);margin:0 .22em;}
  .frac{display:inline-grid;grid-template-rows:auto auto;vertical-align:middle;text-align:center;font-style:normal;line-height:1;}
  .frac .top{border-bottom:2px solid currentColor;padding:0 .2em .08em;}
  .frac .bottom{padding:.08em .2em 0;}
  sup,sub{font-size:.68em;line-height:0;}
  .q-strip{display:flex;gap:8px;justify-content:center;flex-wrap:wrap;padding:2px 0;}
  .q-dot{width:52px;height:52px;border-radius:12px;border:2px solid var(--line);background:#fff;
    font-size:15px;font-weight:900;display:flex;flex-direction:column;align-items:center;justify-content:center;
    cursor:pointer;line-height:1;transition:border-color .12s,background .12s;}
  .q-dot.current{border-color:var(--accent);color:var(--accent);background:var(--accent-soft);}
  .q-dot.correct{border-color:var(--correct);background:var(--correct-soft);color:var(--correct);}
  .q-dot.incorrect{border-color:var(--incorrect);background:var(--incorrect-soft);color:var(--incorrect);}
  .q-dot .q-num{font-size:16px;font-weight:900;}
  .q-dot .q-icon{font-size:12px;font-weight:900;line-height:1.2;}
  @media (max-width:560px){
    body{font-size:18px;}
    #app{padding:14px;}
    .prompt{font-size:22px;}
    .expression{font-size:30px;}
    .choices{grid-template-columns:1fr;}
    .choice{font-size:20px;}
  }
</style>
</head>
<body>
<div id="app">
  <div class="topline">
    <div class="pill" id="questionPill">Question 1</div>
    <div class="pill" id="scorePill">Score 0/0</div>
    <div class="meter" aria-hidden="true"><span id="progressBar"></span></div>
  </div>
  <div class="card">
    <div id="prompt" class="prompt"></div>
    <div id="expression" class="expression" style="display:none"></div>
  </div>
  <div id="choices" class="choices"></div>
  <div class="row">
    <button id="hintBtn" onclick="showHint()">Hint</button>
    <button id="checkBtn" class="primary" onclick="checkAnswer()">Check</button>
    <button id="prevBtn" class="icon-btn" onclick="navigatePrev()">&#8592;</button>
    <button id="nextBtn" class="icon-btn" onclick="navigateNext()">&#8594;</button>
  </div>
  <div id="feedback" class="feedback"></div>
  <div class="row" style="justify-content:flex-end;">
    <button id="retryBtn" class="hidden" onclick="retryMissed()">&#8635; Retry Missed</button>
    <button id="submitBtn" class="success hidden" onclick="submitWidget()">Submit &#10003;</button>
  </div>
  <div id="qStrip" class="q-strip"></div>
</div>
<script>
(function(){
  "use strict";
  var documentModel=null, state=null, applying=false;
  var canSubmitToTeacher=false;

  function $(id){ return document.getElementById(id); }
  function arr(value){ return Array.isArray(value) ? value : []; }
  function setArray(value){ return Array.from(new Set(arr(value))); }
  function escapeHTML(value){
    return String(value == null ? "" : value).replace(/[&<>"']/g,function(ch){
      return {"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[ch];
    });
  }
  function replaceCommandSymbols(value){
    return value
      .replace(/\\leq?/g,"&le;").replace(/\\geq?/g,"&ge;").replace(/\\ne(?:q)?/g,"&ne;")
      .replace(/\\times/g,"&times;").replace(/\\cdot/g,"&middot;").replace(/\\pm/g,"&plusmn;")
      .replace(/\\theta/g,"&theta;").replace(/\\pi/g,"&pi;").replace(/\\alpha/g,"&alpha;")
      .replace(/\\beta/g,"&beta;").replace(/\\Delta/g,"&Delta;").replace(/\\infty/g,"&infin;").replace(/\\div/g,"&divide;");
  }
  function balancedGroup(source,index){
    if(source[index] !== "{") return null;
    var depth=0;
    for(var i=index;i<source.length;i++){
      if(source[i] === "{") depth++;
      if(source[i] === "}") depth--;
      if(depth === 0) return {text:source.slice(index+1,i), end:i+1};
    }
    return null;
  }
  function latexHTML(source){
    var s=escapeHTML(source);
    var guard=0;
    while(s.indexOf("\\frac{") !== -1 && guard++ < 20){
      var start=s.indexOf("\\frac{");
      var top=balancedGroup(s,start+5);
      if(!top) break;
      var bottom=balancedGroup(s,top.end);
      if(!bottom) break;
      var repl='<span class="frac"><span class="top">'+latexHTML(top.text)+'</span><span class="bottom">'+latexHTML(bottom.text)+'</span></span>';
      s=s.slice(0,start)+repl+s.slice(bottom.end);
    }
    guard=0;
    while(s.indexOf("\\sqrt{") !== -1 && guard++ < 20){
      var rootStart=s.indexOf("\\sqrt{");
      var root=balancedGroup(s,rootStart+5);
      if(!root) break;
      s=s.slice(0,rootStart)+"&radic;("+latexHTML(root.text)+")"+s.slice(root.end);
    }
    s=s.replace(/\^\{([^{}]+)\}/g,"<sup>$1</sup>")
       .replace(/_\{([^{}]+)\}/g,"<sub>$1</sub>")
       .replace(/\^([A-Za-z0-9+\-]+)/g,"<sup>$1</sup>")
       .replace(/_([A-Za-z0-9+\-]+)/g,"<sub>$1</sub>");
    return replaceCommandSymbols(s);
  }
  function renderMathText(source){
    var text=String(source || "");
    var out="", i=0;
    while(i<text.length){
      var dollar=text.indexOf("$",i);
      var paren=text.indexOf("\\(",i);
      var next=-1, mode="";
      if(dollar>=0 && (paren<0 || dollar<paren)){ next=dollar; mode="$"; }
      else if(paren>=0){ next=paren; mode="\\("; }
      if(next<0){ out+=escapeHTML(text.slice(i)); break; }
      out+=escapeHTML(text.slice(i,next));
      var close=mode==="$" ? text.indexOf("$",next+1) : text.indexOf("\\)",next+2);
      if(close<0){ out+=escapeHTML(text.slice(next)); break; }
      var body=mode==="$" ? text.slice(next+1,close) : text.slice(next+2,close);
      out+='<span class="math">'+latexHTML(body)+'</span>';
      i=mode==="$" ? close+1 : close+2;
    }
    return out;
  }
  // Returns a complete flow object matching Swift's WidgetActivityAttemptFlowState fields.
  // Swift's synthesized Codable requires ALL non-optional fields in JSON — sending flow:{}
  // causes JSONDecoder to throw, so runtimeState never updates on the Swift side.
  function defaultFlow(){
    return {isShowingFinalScore:false,isRetryingMissed:false,isReviewingAnswers:null,
      retryQuestionIDs:[],retryQuestionIndex:0,skippedRetryQuestionIDs:[],hasSubmittedScore:false};
  }
  function defaultState(doc){
    var qo=doc.questions.map(function(_,i){ return i; });
    var choiceOrders={};
    doc.questions.forEach(function(q){ choiceOrders[q.id]=q.choices.map(function(c){ return c.id; }); });
    return {currentQuestionIndex:0,questionOrder:qo,choiceOrders:choiceOrders,score:0,attempts:0,streak:0,longestStreak:0,
      hintLevel:0,feedbackKind:"neutral",feedbackMessage:null,selectedChoiceID:null,submittedChoiceID:null,
      answeredQuestionIDs:[],correctlyAnsweredQuestionIDs:[],questionAttempts:{},
      submittedChoiceIDsByQuestionID:{},flow:defaultFlow()};
  }
  function normalizeState(doc,incoming){
    var s=Object.assign(defaultState(doc), incoming || {});
    if(!Array.isArray(s.questionOrder) || s.questionOrder.length !== doc.questions.length) s.questionOrder=defaultState(doc).questionOrder;
    if(!s.choiceOrders) s.choiceOrders=defaultState(doc).choiceOrders;
    s.answeredQuestionIDs=setArray(s.answeredQuestionIDs);
    s.correctlyAnsweredQuestionIDs=setArray(s.correctlyAnsweredQuestionIDs);
    s.questionAttempts=s.questionAttempts || {};
    s.submittedChoiceIDsByQuestionID=s.submittedChoiceIDsByQuestionID || {};
    // Always merge with defaults so Swift receives all required WidgetActivityAttemptFlowState fields.
    s.flow=Object.assign(defaultFlow(), s.flow || {});
    s.flow.skippedRetryQuestionIDs=setArray(s.flow.skippedRetryQuestionIDs);
    s.flow.retryQuestionIDs=arr(s.flow.retryQuestionIDs);
    return s;
  }
  function currentQuestion(){
    if(!documentModel || !documentModel.questions.length) return null;
    var idx=state.questionOrder[state.currentQuestionIndex] || 0;
    return documentModel.questions[idx] || documentModel.questions[0];
  }
  function currentChoices(q){
    var order=state.choiceOrders[q.id] || q.choices.map(function(c){ return c.id; });
    return order.map(function(id){ return q.choices.find(function(c){ return c.id===id; }); }).filter(Boolean);
  }
  function questionIndexForID(questionID){
    var docIndex=documentModel.questions.findIndex(function(q){ return q.id===questionID; });
    if(docIndex<0) return -1;
    return state.questionOrder.indexOf(docIndex);
  }
  function missedQuestionIDs(){
    return documentModel.questions
      .map(function(q){ return q.id; })
      .filter(function(id){
        return state.answeredQuestionIDs.indexOf(id)>=0 && state.correctlyAnsweredQuestionIDs.indexOf(id)<0;
      });
  }
  function removeFromArray(source,value){
    return arr(source).filter(function(item){ return item!==value; });
  }
  function publish(){
    if(applying) return;
    if(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mathBoardScoredWidgetState){
      window.webkit.messageHandlers.mathBoardScoredWidgetState.postMessage(JSON.stringify(state));
    }
  }
  function renderNavStrip(){
    if(!documentModel || !state) return;
    var strip=$("qStrip");
    strip.innerHTML="";
    state.questionOrder.forEach(function(docIdx,orderIdx){
      var q=documentModel.questions[docIdx];
      var btn=document.createElement("button");
      btn.className="q-dot";
      var isCorrect=state.correctlyAnsweredQuestionIDs.indexOf(q.id)>=0;
      var isAnswered=state.answeredQuestionIDs.indexOf(q.id)>=0;
      if(isCorrect) btn.classList.add("correct");
      else if(isAnswered) btn.classList.add("incorrect");
      if(orderIdx===state.currentQuestionIndex) btn.classList.add("current");
      var icon=isCorrect?"✓":(isAnswered?"✗":"");
      btn.innerHTML='<span class="q-num">'+escapeHTML(String(orderIdx+1))+'</span>'+(icon?'<span class="q-icon">'+escapeHTML(icon)+'</span>':"");
      var capturedIdx=orderIdx;
      btn.onclick=function(){ navigateToIndex(capturedIdx); };
      strip.appendChild(btn);
    });
  }
  function render(){
    if(!documentModel || !state) return;
    var total=documentModel.questions.length;
    var q=currentQuestion();
    if(!q){ $("prompt").textContent="No questions available."; return; }
    var answered=state.answeredQuestionIDs.length;
    var allAnswered=answered>=total;
    var missed=missedQuestionIDs();

    $("questionPill").textContent="Question "+(state.currentQuestionIndex+1)+" of "+total;
    $("scorePill").textContent="Score "+state.score+"/"+total;
    $("progressBar").style.width=(total ? (answered/total*100) : 0)+"%";
    $("prompt").innerHTML=renderMathText(q.prompt);
    if(q.expression){
      $("expression").style.display="flex";
      $("expression").innerHTML=renderMathText("$"+q.expression+"$");
    }else{
      $("expression").style.display="none";
    }

    var locked=state.answeredQuestionIDs.indexOf(q.id)>=0;
    var submittedID=state.submittedChoiceIDsByQuestionID && state.submittedChoiceIDsByQuestionID[q.id];
    $("choices").innerHTML="";
    currentChoices(q).forEach(function(choice){
      var btn=document.createElement("button");
      btn.className="choice";
      if(!locked && choice.id===state.selectedChoiceID) btn.classList.add("selected");
      if(locked && choice.isCorrect) btn.classList.add("correct");
      if(locked && choice.id===submittedID && !choice.isCorrect) btn.classList.add("incorrect");
      btn.disabled=locked;
      btn.innerHTML='<span class="badge">'+escapeHTML(choice.id.toUpperCase())+'</span><span>'+renderMathText(choice.label)+'</span>';
      btn.onclick=function(){ state.selectedChoiceID=choice.id; state.feedbackMessage=null; state.feedbackKind="neutral"; render(); publish(); };
      $("choices").appendChild(btn);
    });

    $("hintBtn").disabled=locked || state.hintLevel>=arr(q.hints).length;
    $("checkBtn").disabled=locked || !state.selectedChoiceID;
    $("prevBtn").disabled=state.currentQuestionIndex<=0;
    $("nextBtn").disabled=state.currentQuestionIndex>=total-1;

    // Retry Missed only appears after ALL questions are answered and at least one was missed
    var retryBtn=$("retryBtn");
    if(allAnswered && missed.length>0){
      retryBtn.classList.remove("hidden");
    }else{
      retryBtn.classList.add("hidden");
    }

    // Submit only appears when Firebase scoring is available; enabled once all questions answered
    var submitBtn=$("submitBtn");
    if(canSubmitToTeacher){
      submitBtn.classList.remove("hidden");
      submitBtn.disabled=!allAnswered;
    }else{
      submitBtn.classList.add("hidden");
    }

    var feedback=$("feedback");
    feedback.className="feedback "+(state.feedbackKind||"neutral");
    feedback.innerHTML=renderMathText(state.feedbackMessage||"");

    renderNavStrip();
  }
  window.navigateToIndex=function(idx){
    if(!documentModel || idx<0 || idx>=documentModel.questions.length) return;
    state.currentQuestionIndex=idx;
    var q=currentQuestion();
    var prevSubmitted=q && state.submittedChoiceIDsByQuestionID && state.submittedChoiceIDsByQuestionID[q.id];
    state.selectedChoiceID=prevSubmitted||null;
    state.submittedChoiceID=prevSubmitted||null;
    state.hintLevel=0;
    state.feedbackMessage=null;
    state.feedbackKind="neutral";
    render(); publish();
  };
  window.navigatePrev=function(){
    if(state && state.currentQuestionIndex>0) navigateToIndex(state.currentQuestionIndex-1);
  };
  window.navigateNext=function(){
    if(state && documentModel && state.currentQuestionIndex<documentModel.questions.length-1)
      navigateToIndex(state.currentQuestionIndex+1);
  };
  window.showHint=function(){
    var q=currentQuestion();
    if(!q || state.hintLevel>=arr(q.hints).length) return;
    state.hintLevel++;
    state.feedbackKind="warning";
    state.feedbackMessage="Hint "+state.hintLevel+": "+q.hints[state.hintLevel-1];
    render(); publish();
  };
  window.checkAnswer=function(){
    var q=currentQuestion();
    if(!q || !state.selectedChoiceID || state.answeredQuestionIDs.indexOf(q.id)>=0) return;
    var choice=q.choices.find(function(c){ return c.id===state.selectedChoiceID; });
    if(!choice) return;
    state.submittedChoiceID=choice.id;
    state.submittedChoiceIDsByQuestionID[q.id]=choice.id;
    state.attempts++;
    state.questionAttempts[q.id]=(state.questionAttempts[q.id]||0)+1;
    state.answeredQuestionIDs.push(q.id);
    if(choice.isCorrect){
      if(state.correctlyAnsweredQuestionIDs.indexOf(q.id)<0){
        state.correctlyAnsweredQuestionIDs.push(q.id);
        state.score++;
      }
      state.streak++;
      state.longestStreak=Math.max(state.longestStreak,state.streak);
      state.feedbackKind="correct";
      state.feedbackMessage=choice.feedback||q.correctFeedback||(documentModel.feedback&&documentModel.feedback.defaultCorrect)||"Correct.";
    }else{
      state.streak=0;
      state.feedbackKind="incorrect";
      state.feedbackMessage=choice.feedback||q.incorrectFeedback||(documentModel.feedback&&documentModel.feedback.defaultIncorrect)||"Not quite.";
    }
    render(); publish();
  };
  window.retryMissed=function(){
    var missed=missedQuestionIDs();
    if(!missed.length) return;
    var questionID=missed[0];
    var nextIndex=questionIndexForID(questionID);
    if(nextIndex<0) return;
    // Reset this specific question so the student can try again from scratch
    state.answeredQuestionIDs=removeFromArray(state.answeredQuestionIDs,questionID);
    delete state.submittedChoiceIDsByQuestionID[questionID];
    state.selectedChoiceID=null;
    state.submittedChoiceID=null;
    navigateToIndex(nextIndex);
  };
  window.resetWidget=function(){
    if(!documentModel) return;
    state=defaultState(documentModel);
    render(); publish();
  };
  window.submitWidget=function(){
    if(!canSubmitToTeacher || !documentModel || state.answeredQuestionIDs.length<documentModel.questions.length) return;
    state.flow.hasSubmittedScore=true;
    publish();
    if(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mathBoardScoredWidgetSubmit){
      window.webkit.messageHandlers.mathBoardScoredWidgetSubmit.postMessage("submit");
    }
  };
  window.MathBoardScoredWidget={
    applyPayload:function(payload){
      applying=true;
      try{
        documentModel=payload.document;
        canSubmitToTeacher=!!payload.canSubmitToTeacher;
        state=normalizeState(documentModel,payload.runtimeState);
        render();
      }finally{
        applying=false;
      }
    }
  };
})();
</script>
</body>
</html>
"""#
}

#if os(iOS)
extension ScoredHTMLMultipleChoiceWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        dismantle(uiView)
    }
}
#elseif os(macOS)
extension ScoredHTMLMultipleChoiceWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        dismantle(nsView)
    }
}
#endif
