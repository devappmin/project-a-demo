# Project A 작업 규칙

## 시작할 때

1. `docs/PROJECT_STATUS.md`와 `docs/ROADMAP.md`를 읽는다.
2. `git status --short`로 기존 변경을 확인하고 보존한다.
3. 작업 범위와 관련 테스트를 확인한다.

## 저장소 범위

- `project-a-demo`만 수정한다.
- deprecated `project-a`는 수정하지 않는다.

## Git 작업 방식

- 기본적으로 현재 `main`에서 작업한다.
- 요청 없이는 branch, worktree, PR을 만들지 않는다.
- 의미 있는 단위마다 semantic commit을 남긴다.

## 구현 방식

- 기능과 버그 수정은 테스트를 먼저 작성한다.
- 실패 원인을 확인한 뒤 최소 변경으로 GREEN을 만든다.
- 사용자의 기존 변경과 무관한 파일을 정리하거나 되돌리지 않는다.

## 표준 검증

- Godot 코드와 씬은 가장 좁은 관련 `python tools/project.py test --filter ...`를 먼저 실행한다.
- Python 도구와 문서는 관련 `python -m unittest tests/python/test_파일.py -v`를 먼저 실행한다.
- 완료 전에는 `python tools/project.py check`를 실행한다.

## Godot 프로젝트 불변조건

- Godot 4.7을 사용한다.
- 640x360 정수 픽셀 렌더링을 유지한다.
- Autoload는 정확히 세 개만 유지한다.
- 런타임은 오프라인으로 동작한다.
- 런타임에 Notion, 토큰, 네트워크 의존성을 추가하지 않는다.

## 대화와 콘텐츠 작성

- 대화와 분기 콘텐츠는 `docs/dialogue-authoring-guide.md`와 `docs/narrative-state-reference.md`를 따른다.
- 작성자에게 보이는 한국어 용어를 보존하고 내부 키를 작성 산문에 노출하지 않는다.

## 문서 갱신

- 현재 상태 변경은 `docs/PROJECT_STATUS.md`에 반영한다.
- 로드맵 변경은 `docs/ROADMAP.md`에 반영한다.
- 구조 변경은 `docs/ARCHITECTURE.md`에 반영한다.
- 작성 UX 변경은 `docs/dialogue-authoring-guide.md`에 반영한다.

## 완료할 때

1. 관련 테스트와 전체 검증 결과를 확인한다.
2. 변경 사실을 소유한 추적 문서를 갱신한다.
3. commit, 검증 결과, 남은 수동 수락 항목을 보고한다.
