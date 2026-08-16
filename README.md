# Project A Demo

Godot 4.7 기반 2D 픽셀 탑다운 어드벤처 게임입니다. 이동과 상호작용보다 대화, 선택, 조건에 따른 이야기 변화가 중심입니다.

## 현재 플레이 가능 범위

타이틀에서 새 게임 또는 저장을 시작해 기초 방과 기초 홀을 오갈 수 있습니다. 거울을 조사하면 이름, 초상화, 표정, 선택지가 있는 대화가 진행되며, 중요한 선택은 자동 저장됩니다. 자동 저장 1개와 수동 슬롯 5개는 맵·플레이어·서사·월드·대화 상태를 복원하고 백업 복구를 지원합니다.

## 요구 사항

- Python 3.9 이상 (`python3`는 `python`을 대신할 수 있음)
- Godot 4.7

## 처음 실행하기

프로젝트 루트에서 환경을 확인한 뒤 검증을 실행합니다.

```bash
python tools/project.py doctor
python tools/project.py check
```

Godot 실행 파일을 자동으로 찾지 못하면 한 번만 직접 지정할 수 있습니다.

```bash
python tools/project.py check --godot /path/to/godot
```

## 조작법

- 이동: `WASD` 또는 방향 키
- 달리기: `Shift`
- 상호작용·대화 진행: `E`
- 메뉴 열기·닫기: `Esc`

## 프로젝트 검증

전체 검증은 Python 테스트, Godot 테스트, 에디터 로드, 헤드리스 부팅을 차례로 실행합니다.

```bash
python tools/project.py check
python tools/project.py test --filter dialogue
```

## 대화 작성

대화는 한국어 문서에서 작성하고 정규화된 작성 데이터와 생성된 런타임 스냅샷으로 반영합니다. 형식과 게시 절차는 [대화 작성 가이드](docs/dialogue-authoring-guide.md)를 따르세요.

## 프로젝트 문서

- [프로젝트 현재 상태](docs/PROJECT_STATUS.md)
- [프로젝트 로드맵](docs/ROADMAP.md)
- [프로젝트 아키텍처](docs/ARCHITECTURE.md)
- [대화 작성 가이드](docs/dialogue-authoring-guide.md)

## 현재 작업 방향

다음 구현 목표는 인벤토리, 퀘스트 단계, 조건부 이벤트와 대화 효과를 하나의 저장 가능한 플레이 기반으로 연결하는 것입니다. 세부 순서는 [프로젝트 로드맵](docs/ROADMAP.md)에서 관리합니다.
