# Customer Intent Demo — Electron UI

Front-end desktop (Electron) com visual inspirado no OpenShift Console para demonstrar roteamento via backend Quarkus.

## Pré-requisitos

- Node.js 18+
- Backend Quarkus em execução no cluster

## Executar no cluster (OpenShift)

A UI web usa nginx no namespace `customer-intent-demo` e faz proxy para o Quarkus:

```bash
oc apply -f ../openshift/15-demo-ui.yaml
oc start-build customer-intent-demo-ui \
  --from-dir=. \
  -n customer-intent-demo --wait
```

Route: `customer-intent-demo-ui` no mesmo namespace do backend.

## Executar localmente (Electron)

```bash
cd customer-intent-demo/demo-electron
npm install
npm start
```

Se houver erro de certificado TLS no cluster de lab:

```bash
npm run start:insecure
```

## Funcionalidades

- **6 casos de uso** pré-configurados (transferência, ATM, ambíguo, cartão, senha, falha)
- Tabela com campos retornados pela IA + regra Quarkus:
  - intenção, departamento, confiança, decisão, fila, versão do modelo
- Botões **Classificar selecionado** e **Executar todos**
- URL do backend editável (default: route do cluster)

## Backend padrão

```
https://customer-intent-backend-customer-intent-demo.apps.tiago-cluster.sandbox897.opentlc.com/api/v1/routing
```

## Apresentação

1. Explique: modelo → intenção + confiança; Quarkus → decisão + fila
2. Execute **Executar todos (6)**
3. Destaque linha ambígua com `HUMAN_REVIEW`
4. Compare departamentos nas linhas `AUTO_ROUTE`
