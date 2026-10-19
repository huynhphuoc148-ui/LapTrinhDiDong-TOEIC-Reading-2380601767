"use strict";

(() => {
  let editingDraftId = null;
  const examJson = document.getElementById("examJson");
  const createButton = document.getElementById("createExam");
  const previewRoot = document.getElementById("preview");

  const importPanel = document.createElement("div");
  importPanel.className = "card";
  const importHeading = document.createElement("strong");
  importHeading.textContent = "Nhập đề từ Word (.docx)";
  const importHint = document.createElement("p");
  importHint.className = "hint";
  importHint.textContent =
    "DOCX phải theo quy ước thẻ bên dưới. Hệ thống kiểm tra toàn bộ trước khi tạo bản nháp; file sai không ghi một phần vào cơ sở dữ liệu.";
  const fileInput = document.createElement("input");
  fileInput.type = "file";
  fileInput.accept =
    ".docx,application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  fileInput.setAttribute("aria-label", "Chọn file đề thi DOCX");
  const importButton = document.createElement("button");
  importButton.type = "button";
  importButton.className = "secondary";
  importButton.textContent = "Kiểm tra và nhập Word";
  const tagDetails = document.createElement("details");
  const tagSummary = document.createElement("summary");
  tagSummary.textContent = "Quy ước thẻ DOCX";
  const tagExample = document.createElement("pre");
  tagExample.textContent = [
    "[TOEIC_EXAM]",
    "[TITLE] Tên đề",
    "[DURATION_MINUTES] 75",
    "[PART 5]",
    "[SHUFFLE_QUESTIONS] false",
    "[QUESTION 101]",
    "[SHUFFLE_OPTIONS] false",
    "[STEM]",
    "Nội dung câu hỏi...",
    "[CHOICE A]",
    "Lựa chọn A...",
    "[CHOICE B]",
    "Lựa chọn B...",
    "[CHOICE C]",
    "Lựa chọn C...",
    "[CHOICE D]",
    "Lựa chọn D...",
    "[ANSWER] B",
    "[HINT]",
    "Gợi ý...",
    "[EXPLANATION]",
    "Giải thích...",
    "[END_QUESTION]",
    "[END_PART]",
    "[PART 6]",
    "[GROUP]",
    "[SHUFFLE_QUESTIONS] false",
    "[PASSAGE]",
    "Đoạn đọc; chèn ảnh Word tại vị trí cần hiển thị.",
    "Chỗ trống Part 6 viết đúng dạng {{131}}.",
    "[END_PASSAGE]",
    "[QUESTION 131]",
    "... đủ bốn lựa chọn, [ANSWER], [HINT], [EXPLANATION], [END_QUESTION]",
    "... câu 132–146 trong các nhóm bốn câu",
    "[END_GROUP]",
    "[END_PART]",
    "[PART 7]",
    "[GROUP]",
    "[PASSAGE]",
    "Đoạn đọc Part 7 và ảnh theo thứ tự xuất hiện.",
    "[END_PASSAGE]",
    "... câu 147–200",
    "[END_GROUP]",
    "[END_PART]",
  ].join("\n");
  tagDetails.append(tagSummary, tagExample);
  const importActions = document.createElement("div");
  importActions.className = "actions";
  importActions.append(importButton);
  importPanel.append(
    importHeading,
    importHint,
    fileInput,
    importActions,
    tagDetails,
  );
  examJson.parentElement.insertBefore(importPanel, examJson);

  const cancelEdit = document.createElement("button");
  cancelEdit.type = "button";
  cancelEdit.className = "secondary";
  cancelEdit.textContent = "Hủy sửa nháp";
  cancelEdit.hidden = true;
  cancelEdit.addEventListener("click", () => resetDraftEditor());
  createButton.parentElement.append(cancelEdit);

  function resetDraftEditor() {
    editingDraftId = null;
    createButton.textContent = "Kiểm tra và lưu bản nháp";
    cancelEdit.hidden = true;
  }

  async function readJsonResponse(response) {
    let data;
    try {
      data = await response.json();
    } catch (_) {
      throw new Error("Backend không trả JSON. Kiểm tra log máy chủ.");
    }
    if (!response.ok || data.success === false) {
      throw new Error(
        data.message || data.error?.message || `Lỗi HTTP ${response.status}`,
      );
    }
    return data.__abp ? data.result : data;
  }

  function appendRichContent(parent, value) {
    const content = String(value ?? "");
    const pattern =
      /\[\[TOEIC_IMAGE:(data:image\/(?:png|jpeg|gif|webp);base64,[A-Za-z0-9+/=]+)\]\]/g;
    let offset = 0;
    let match;
    while ((match = pattern.exec(content)) !== null) {
      if (match.index > offset) {
        const part = document.createElement("pre");
        part.textContent = content.slice(offset, match.index);
        parent.append(part);
      }
      const image = document.createElement("img");
      image.src = match[1];
      image.alt = "Ảnh trong đề thi";
      image.loading = "lazy";
      image.style.maxWidth = "100%";
      image.style.height = "auto";
      image.style.objectFit = "contain";
      parent.append(image);
      offset = pattern.lastIndex;
    }
    if (offset < content.length) {
      const part = document.createElement("pre");
      part.textContent = content.slice(offset);
      parent.append(part);
    }
  }

  function renderExam(exam) {
    previewRoot.replaceChildren();
    const title = document.createElement("h3");
    title.textContent = exam.title || "Đề chưa có tên";
    previewRoot.append(title);
    for (const block of exam.blocks || []) {
      const part = document.createElement("section");
      part.className = "card";
      const heading = document.createElement("h4");
      heading.textContent = `Part ${block.part} · ${block.questions?.length || 0} câu`;
      part.append(heading);
      for (const passage of block.passages || []) {
        const passageView = document.createElement("div");
        passageView.className = "hint";
        appendRichContent(passageView, passage);
        part.append(passageView);
      }
      for (const question of block.questions || []) {
        const card = document.createElement("div");
        card.className = "card";
        const questionTitle = document.createElement("strong");
        questionTitle.textContent = `Câu ${question.number}`;
        card.append(questionTitle);
        const stem = document.createElement("div");
        appendRichContent(stem, question.stem);
        card.append(stem);
        for (const label of ["A", "B", "C", "D"]) {
          const choice = document.createElement("div");
          choice.className = "hint";
          const labelNode = document.createElement("strong");
          labelNode.textContent = `${label}. `;
          choice.append(labelNode);
          appendRichContent(choice, question.choices?.[label]);
          card.append(choice);
        }
        const answer = document.createElement("p");
        answer.className = "hint";
        answer.textContent = `Đáp án ${question.answer || "chưa có"}`;
        card.append(answer);
        const explanation = document.createElement("p");
        explanation.className = "hint";
        appendRichContent(
          explanation,
          `Gợi ý: ${question.hint || ""}\nGiải thích: ${question.explanation || ""}`,
        );
        card.append(explanation);
        part.append(card);
      }
      previewRoot.append(part);
    }
    previewRoot.closest("details").open = true;
  }

  async function openDraft(versionId) {
    const draft = await api(`/api/toeic/teacher/exams/${versionId}/draft`);
    editingDraftId = versionId;
    examJson.value = JSON.stringify(draft, null, 2);
    createButton.textContent = "Lưu sửa đổi thành phiên bản nháp mới";
    cancelEdit.hidden = false;
    renderExam(draft);
    document
      .getElementById("examJson")
      .scrollIntoView({ behavior: "smooth", block: "center" });
  }

  function addDraftActions() {
    for (const card of document.querySelectorAll("#exams .card")) {
      if (card.dataset.draftActions) continue;
      const meta = card.querySelector(".hint")?.textContent || "";
      const match = meta.match(/#(\d+)\s*·\s*Draft/);
      if (!match) continue;
      card.dataset.draftActions = "true";
      const button = document.createElement("button");
      button.type = "button";
      button.className = "secondary";
      button.textContent = "Xem và sửa bản nháp";
      button.addEventListener("click", () =>
        run(() => openDraft(Number(match[1]))),
      );
      card.append(button);
    }
  }

  const examListObserver = new MutationObserver(addDraftActions);
  examListObserver.observe(document.getElementById("exams"), {
    childList: true,
    subtree: true,
  });

  importButton.addEventListener("click", () =>
    run(async () => {
      const file = fileInput.files?.[0];
      if (!file) throw new Error("Chọn file DOCX trước khi nhập.");
      if (!file.name.toLowerCase().endsWith(".docx"))
        throw new Error("Chỉ nhận file .docx.");
      importButton.disabled = true;
      try {
        const form = new FormData();
        form.append("file", file);
        const response = await fetch("/api/toeic/teacher/exams/import", {
          method: "POST",
          credentials: "omit",
          headers: token ? { Authorization: `Bearer ${token}` } : {},
          body: form,
        });
        const result = await readJsonResponse(response);
        await load();
        await openDraft(result.id);
        tell(`DOCX hợp lệ. Bản nháp #${result.id} đã được tạo để rà soát.`);
      } finally {
        importButton.disabled = false;
      }
    }),
  );

  document.getElementById("previewButton").onclick = () =>
    run(() => renderExam(JSON.parse(examJson.value)));
  createButton.onclick = () =>
    run(async () => {
      let exam;
      try {
        exam = JSON.parse(examJson.value);
      } catch (_) {
        throw new Error("JSON đề thi không hợp lệ.");
      }
      createButton.disabled = true;
      try {
        if (editingDraftId == null) {
          const result = await api("/api/toeic/teacher/exams", "POST", exam);
          await load();
          await openDraft(result.id);
          tell(`Đã lưu bản nháp #${result.id}.`);
        } else {
          const result = await api(
            `/api/toeic/teacher/exams/${editingDraftId}/draft`,
            "PUT",
            exam,
          );
          resetDraftEditor();
          await load();
          await openDraft(result.id);
          tell(
            `Đã lưu phiên bản nháp mới #${result.id}; các phiên bản/lượt thi trước được giữ nguyên.`,
          );
        }
      } finally {
        createButton.disabled = false;
      }
    });
})();
