## Gemini CLI Integration
사용자가 "Gemini와 상의하면서 진행해줘" 또는 유사한 표현을 사용할 경우:
1. 요구사항을 $PROMPT 환경 변수에 저장
2. `gemini -m gemini-3-pro-preview -p "$PROMPT" --output-format stream-json` 실행
3. Gemini 응답을 보여주고, Claude의 해설 추가
4. 코드 및 해결 방안등 결과를 비교하여 최적안 선택

## Copilot CLI Integration
사용자가 "Copilot하고 상의하면서 진행해줘" 또는 유사한 표현을 사용할 경우:
1. 요구사항을 $PROMPT 환경 변수에 저장
2. `copilot --model gpt-5.1-codex -p "$PROMPT"` 실행
3. `copilot --model claude-opus-4.5 -p "$PROMPT"` 실행
4. `copilot --model gemini-3-pro-preview -p "$PROMPT"` 실행
5. 각각 3가지 모델에 대한 copilot 실행 후 결과를 기반으로 Claude의 해설 추가
6. 코드 및 해결 방안등 결과를 비교하여 최적안 선택
7. 만약 copilot이 동작하지 않는다면 다시 수행

