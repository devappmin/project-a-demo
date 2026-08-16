# 프로젝트 아키텍처

## 전체 흐름

`AppRoot`는 게임 실행 동안 유지되고 맵만 교체한다.

```text
/root
├─ GameSession       (Autoload)
├─ SceneDirector     (Autoload)
├─ SaveService       (Autoload)
└─ AppRoot
   ├─ ServiceLayer
   │  ├─ DialogueService
   │  ├─ DialogueActionAdapter
   │  └─ DoorActionAdapter
   ├─ WorldHost
   │  └─ CurrentMap 또는 비어 있음
   └─ UILayer
      ├─ ScreenFade
      ├─ InteractionPrompt
      ├─ DialogueView
      ├─ TitleMenu
      ├─ PauseMenu
      ├─ SlotMenu
      └─ ToastLayer
```

## 디렉터리 책임

- `app/`: 부트스트랩, 전역 세션, 맵 전환, 저장 서비스
- `game/`: 플레이어, 상호작용, 서사 런타임, 월드 모델
- `content/`: 맵과 상호작용 가능한 씬 콘텐츠
- `data/`: 캐릭터·맵 정의와 작성·생성 대화 데이터
- `ui/`: 대화, 프롬프트, 메뉴, 전환 화면
- `tests/`: Godot 통합·단위 테스트와 Python 프로젝트 도구 테스트
- `tools/`: 프로젝트 검증과 대화 가져오기 도구

## 런타임 소유권

- `GameSession`: mode, `NarrativeState`, `WorldState`, play time.
- `SceneDirector`: current map, persistent player, transition transaction.
- `SaveService`: six-slot capture, repository orchestration, transactional restore.
- `AppRoot`: local service wiring and UI, not persistent state ownership.

전역 서비스는 이 세 가지뿐이며, `SaveRepository`와 저장 데이터는 일반 클래스다.

## 플레이어와 맵 수명 주기

`SceneDirector`가 플레이어를 한 번 생성해 유지한다. 맵을 바꿀 때 새 맵과 스폰 지점을 먼저 검증하고, 플레이어 본체와 시각 표현을 새 맵의 적절한 루트로 옮긴 뒤 상호작용 연결을 다시 묶는다. 전환 또는 복원에 실패하면 후보 맵만 버리고 기존 맵·플레이어·상태를 되돌린다.

## 상호작용에서 대화까지

Interaction: detector -> router -> event resolver -> dialogue service.

감지기는 현재 대상과 프롬프트를 갱신하고, 라우터는 행동을 어댑터에 전달한다. 대화 어댑터는 `bundle_key + trigger_key`로 이벤트를 선택하며, 문 어댑터는 `SceneDirector` 전환을 요청한다. 새 맵이 확정되면 `AppRoot`가 이전 연결을 해제하고 새 플레이어의 연결을 다시 만든다.

## 상태와 저장 경계

State split: story facts and quest stages in NarrativeState; visual/object-local facts in WorldState.

`SaveService`는 자동 저장 1개와 수동 슬롯 5개를 캡처한다. 복원은 저장 데이터를 먼저 검증하고 맵 전환, 세션·플레이어 상태 적용, 대화 재개, 전환 확정 순서로 처리한다. 어느 단계든 실패하면 트랜잭션으로 기존 플레이와 마지막 정상 슬롯을 보존한다.

## 문서에서 런타임 데이터까지

Authoring: Korean document -> normalized authoring JSON -> schema/compiler -> graph/events/source map/manifest.

런타임은 생성된 로컬 스냅샷만 읽는다. 작성 문서의 형식과 검토 절차는 [대화 작성 가이드](dialogue-authoring-guide.md), 상태 용어는 [서사 상태 참고서](narrative-state-reference.md)를 따른다.

## 테스트 계층

- Python: 프로젝트 명령과 추적 문서의 계약
- Godot 단위·통합: 상태, 대화, 맵 전환, 저장·복원
- 에디터 로드: 스크립트와 리소스 로드
- 헤드리스 부팅: 실제 앱 진입점의 기본 실행
- 수동 수락: 실제 키보드와 화면으로 수직 슬라이스를 확인

전체 게이트는 `python tools/project.py check`로 실행한다.

## 변경할 때 함께 확인할 문서

- 대화 조건·효과·작성 형식: [대화 작성 가이드](dialogue-authoring-guide.md), [서사 상태 참고서](narrative-state-reference.md)
- 현재 기능 범위와 검증 근거: [프로젝트 현재 상태](PROJECT_STATUS.md)
- 다음 기능의 완료 기준: [프로젝트 로드맵](ROADMAP.md)
- 월드·저장 수직 슬라이스의 설계 근거: [설계 문서](superpowers/specs/2026-08-16-world-save-vertical-slice-redesign-design.md)
