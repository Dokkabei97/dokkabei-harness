---
name: web-fetch
description: Fetches web page content using Gemini CLI when Claude's native WebFetch fails or for explicit URL fetching. Returns clean Markdown.
argument-hint: <url> [extraction instruction]
disable-model-invocation: true
allowed-tools: Bash(gemini *)
---

# Web Fetch via Gemini CLI

Gemini CLI의 네이티브 웹 브라우징으로 URL 콘텐츠를 Markdown으로 가져옵니다.
Claude의 WebFetch가 실패했을 때의 폴백 또는 명시적 웹 콘텐츠 요청에 사용합니다.

## When to Use

- Claude의 WebFetch 도구가 실패하거나 접근 불가한 URL일 때
- 웹 페이지 콘텐츠를 깔끔한 Markdown으로 가져오고 싶을 때
- 문서, 기사, API 레퍼런스 등 URL 기반 정보를 조회할 때
- 특정 페이지에서 원하는 부분만 추출하고 싶을 때

## Gemini CLI Status

!`which gemini 2>/dev/null && echo "available" || echo "NOT INSTALLED — npm i -g @google/gemini-cli"`

## Instructions

1. Parse arguments:
   - `$0` = target URL
   - 나머지 = optional extraction/focus instruction

2. Execute:

   ```bash
   URL="<target URL>"
   INSTRUCTION="<optional focus instruction>"

   gemini -m gemini-3-flash-preview -p "다음 URL의 콘텐츠를 가져와서 깔끔한 Markdown으로 변환해줘.

   URL: $URL

   규칙:
   - 코드 블록, 테이블, 리스트, 헤딩 보존
   - 네비게이션, 광고, 푸터, 사이드바 제거
   - 본문 콘텐츠만 반환
   - 페이지 접근 불가 시 에러 설명

   추가 지시: $INSTRUCTION

   콘텐츠만 반환하고, 부가 설명은 생략해줘." --sandbox
   ```

3. Display:
   ```markdown
   **Fetched**: <url>
   **Model**: gemini-3.1-flash-preview

   <content>
   ```

## Notes

- 속도 우선으로 `gemini-3.1-flash-preview` 사용 (웹 fetch에 강력한 모델 불필요)
- Timeout: 120초
- 인증 필요 URL은 실패 → 사용자에게 안내
- 여러 URL은 각각 별도 실행

## Examples

- `/web-fetch https://docs.python.org/3/library/asyncio.html`
- `/web-fetch https://react.dev/reference/react/useState API 레퍼런스 테이블만 추출`
- `/web-fetch https://github.com/user/repo/blob/main/README.md`
