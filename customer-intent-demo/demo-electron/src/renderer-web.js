const DEFAULT_BACKEND = "/api/v1/routing";

const DEMO_CASES = [
  {
    id: "demo-1",
    title: "Transferência pendente",
    text: "My transfer is still pending",
    expected: "AUTO_ROUTE → transfers-support",
  },
  {
    id: "demo-2",
    title: "Saque não reconhecido",
    text: "I do not recognize this cash withdrawal",
    expected: "AUTO_ROUTE → atm-support",
  },
  {
    id: "demo-3",
    title: "Mensagem ambígua",
    text: "something is wrong",
    expected: "HUMAN_REVIEW → human-review-queue",
  },
  {
    id: "demo-4",
    title: "Cartão perdido",
    text: "I lost my card yesterday and need a replacement",
    expected: "AUTO_ROUTE → cards-support",
  },
  {
    id: "demo-5",
    title: "Senha esquecida",
    text: "I forgot my passcode and cannot log in to the app",
    expected: "AUTO_ROUTE → security-identity",
  },
  {
    id: "demo-6",
    title: "Transferência falhou",
    text: "My bank transfer failed and the money left my account",
    expected: "AUTO_ROUTE → transfers-support",
  },
];

let selectedCaseId = DEMO_CASES[0].id;
let backendUrl = DEFAULT_BACKEND;

const backendInput = document.getElementById("backend-url");
const caseList = document.getElementById("case-list");
const resultsBody = document.getElementById("results-body");
const jsonDetail = document.getElementById("json-detail");
const statusText = document.getElementById("status-text");

async function routeRequest({ url, text, correlationId }) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ text, correlationId }),
  });
  const bodyText = await response.text();
  let body;
  try {
    body = JSON.parse(bodyText);
  } catch {
    body = { error: bodyText || response.statusText };
  }
  if (!response.ok) {
    return {
      ok: false,
      status: response.status,
      error: body.error || body.message || bodyText || response.statusText,
    };
  }
  return { ok: true, data: body };
}

function renderCases() {
  caseList.innerHTML = DEMO_CASES.map(
    (item) => `
    <li class="case-item ${item.id === selectedCaseId ? "selected" : ""}" data-id="${item.id}">
      <div class="case-title">${item.title}</div>
      <div class="case-text">"${item.text}"</div>
      <div class="case-expect">Esperado: ${item.expected}</div>
    </li>
  `
  ).join("");

  caseList.querySelectorAll(".case-item").forEach((el) => {
    el.addEventListener("click", () => {
      selectedCaseId = el.dataset.id;
      renderCases();
    });
  });
}

function decisionPill(decision) {
  if (decision === "AUTO_ROUTE") {
    return '<span class="pill pill-auto">AUTO_ROUTE</span>';
  }
  if (decision === "HUMAN_REVIEW") {
    return '<span class="pill pill-review">HUMAN_REVIEW</span>';
  }
  return `<span class="pill pill-error">${decision || "ERRO"}</span>`;
}

function formatConfidence(value) {
  if (typeof value !== "number") {
    return "—";
  }
  const pct = (value * 100).toFixed(1) + "%";
  const css = value >= 0.8 ? "confidence-high" : "confidence-low";
  return `<span class="${css}">${pct}</span>`;
}

function appendResultRow(caseItem, result) {
  if (resultsBody.querySelector(".empty-row")) {
    resultsBody.innerHTML = "";
  }

  const tr = document.createElement("tr");
  if (!result.ok) {
    tr.className = "row-error";
    tr.innerHTML = `
      <td>${caseItem.title}</td>
      <td class="msg-cell">"${caseItem.text}"</td>
      <td colspan="6">Erro ${result.status || ""}: ${result.error}</td>
    `;
    resultsBody.appendChild(tr);
    return;
  }

  const data = result.data;
  tr.innerHTML = `
    <td>${caseItem.title}</td>
    <td class="msg-cell">"${data.text || caseItem.text}"</td>
    <td><code>${data.predictedIntent || "—"}</code></td>
    <td>
      <strong>${data.departmentDisplayName || data.department || "—"}</strong><br />
      <span style="color:var(--text-muted)">${data.department || ""}</span>
    </td>
    <td>${formatConfidence(data.confidence)}</td>
    <td>${decisionPill(data.decision)}</td>
    <td><code>${data.queue || "—"}</code></td>
    <td>${data.modelVersion || "—"}</td>
  `;
  resultsBody.appendChild(tr);
  jsonDetail.textContent = JSON.stringify(data, null, 2);
}

async function routeCase(caseItem) {
  statusText.textContent = `Enviando: ${caseItem.title}...`;
  const result = await routeRequest({
    url: backendUrl,
    text: caseItem.text,
    correlationId: caseItem.id + "-" + Date.now(),
  });
  appendResultRow(caseItem, result);
  statusText.textContent = result.ok
    ? `Concluído: ${caseItem.title}`
    : `Falha: ${caseItem.title}`;
  return result;
}

async function runSelected() {
  const selected = DEMO_CASES.find((item) => item.id === selectedCaseId);
  if (!selected) {
    return;
  }
  await routeCase(selected);
}

async function runAll() {
  resultsBody.innerHTML = "";
  statusText.textContent = "Executando todos os casos...";
  for (const caseItem of DEMO_CASES) {
    await routeCase(caseItem);
  }
  statusText.textContent = "Todos os casos executados.";
}

document.getElementById("run-selected").addEventListener("click", runSelected);
document.getElementById("run-all").addEventListener("click", runAll);
document.getElementById("clear-results").addEventListener("click", () => {
  resultsBody.innerHTML =
    '<tr class="empty-row"><td colspan="8">Selecione um caso ou clique em "Executar todos".</td></tr>';
  jsonDetail.textContent = "{}";
  statusText.textContent = "Pronto";
});

backendInput.value = backendUrl;
renderCases();
