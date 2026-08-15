# 대화 작성 가이드

이 문서는 코드를 열지 않고 Notion에서 대사를 쓰는 사람을 위한 안내서입니다. 평소에는 `Text`, `flow`, `order`, `type`, `speaker`, `expression`, `target_flow`만 보면 됩니다. 이름에 `_json`이 붙은 칸은 개발자와 합의한 때에만 건드리세요.

## 작업할 곳

- [Dialogue Scenes 검색](https://www.notion.so/search?q=Dialogue%20Scenes): 장면의 이름, 상태, 시작 흐름을 정합니다.
- [Dialogue Blocks 검색](https://www.notion.so/search?q=Dialogue%20Blocks): 실제 대사와 선택지를 순서대로 씁니다.
- [Characters 검색](https://www.notion.so/search?q=Characters): 캐릭터 키와 사용할 수 있는 표정을 확인합니다.

링크는 데이터베이스 ID나 인증 정보를 문서에 남기지 않도록 이름 검색으로 열립니다. 검색 결과에서 Project A 기획안 아래의 같은 이름 데이터베이스를 선택하세요.

`foundation.inspect` 장면에는 작성 예시가 준비되어 있습니다. 장면 안의 연결된 블록 표는 현재 장면만 보여 주며, `flow`별로 묶고 `order` 오름차순으로 정렬되어 있습니다. 로직용 JSON 칸은 기본 보기에서 숨겨져 있습니다.

> Notion API 제약 때문에 이 예시를 새 장면용 데이터베이스 템플릿으로 바꾸는 일은 Notion 화면에서 한 번 수동으로 해야 합니다. 템플릿 메뉴에서 `foundation.inspect`의 연결된 블록 보기 구성을 복제하고, 필터의 `scene`을 새 템플릿 페이지로 지정하세요.

## 가장 자주 쓰는 작성 흐름

1. `Dialogue Scenes`에서 장면을 새로 만들고 `scene_key`를 `chapter.place.event`처럼 겹치지 않게 적습니다.
2. 처음에는 `status`를 `Draft`로 둡니다. `start_flow`에는 보통 `main`을 적습니다.
3. 장면 페이지의 연결된 `Dialogue Blocks` 표에서 새 줄을 추가합니다. `scene`은 현재 장면, `flow`는 `main`, `type`은 `line`을 고릅니다.
4. `Text`에 대사를 쓰고, `speaker`와 `expression`을 고릅니다. `expression`은 `Characters`의 해당 캐릭터에 등록된 값만 사용합니다.
5. 같은 흐름 안의 순서는 `order` 숫자로 정합니다. 줄을 옮길 때는 행을 끌어놓기보다 `order`를 바꾸세요. 예를 들어 10, 20, 30처럼 간격을 두면 중간에 15를 쉽게 넣을 수 있습니다.
6. 마지막 `line`이 다른 흐름으로 가야 하면 `target_flow`에 그 흐름 이름을 적습니다. 같은 흐름의 다음 줄로 이어질 때는 비워도 됩니다.
7. 작성 중에는 Godot의 `Notion Dialogue Sync` 패널에서 `Dry Run`을 눌러 확인합니다. 오류 행을 더블클릭하면 문제가 있는 Notion 원문이 열립니다.

## 선택지 만들기

선택지가 나타날 위치에 같은 `flow`를 가진 `choice` 행을 연속으로 만듭니다. 한 행이 선택지 한 개입니다.

| order | type | Text | target_flow |
|---:|---|---|---|
| 10 | choice | 자세히 본다 | inspect |
| 20 | choice | 뒤로 물러난다 | leave |

두 행 사이에 다른 `type`을 넣지 마세요. 각 `target_flow`와 같은 이름의 흐름을 아래에 만들고, 그 흐름의 첫 행부터 결과 대사를 이어 씁니다. 선택 조건이나 선택 직후의 효과가 필요하면 `notes`에 평문으로 “mirror_seen이 참일 때만”, “선택하면 mirror_seen을 참으로”처럼 적고 개발자에게 전달하세요. 개발자가 확인한 뒤 숨겨진 `conditions_json` 또는 `effects_json`을 채웁니다.

`foundation.inspect`에는 별도 `effect` 노드로 `flag_set mirror_seen=true`를 적용하는 예가 있습니다. 장면의 끝에는 `type=end` 행을 두세요.

## 표정 고르기

먼저 `Characters`에서 캐릭터의 `expressions` 목록을 확인한 뒤 블록의 `expression`에서 같은 값을 선택합니다. 원하는 표정이 목록에 없다면 임의 문자열을 만들지 말고 `notes`에 필요한 표정을 적어 개발자에게 요청하세요. `default_expression`은 표정을 새로 정할 때 참고하는 기본값이며, 대사 행의 빈 `expression`을 자동으로 대신하지는 않습니다.

## Draft → Review → Final

- `Draft`: 자유롭게 쓰는 단계입니다. 표정 경고가 있어도 Dry Run 결과를 만들 수 있습니다.
- `Review`: 문장과 분기 흐름을 함께 검토하는 단계입니다. 경고는 보이지만 동기화를 막지는 않습니다.
- `Final`: 게임에 넣을 준비가 끝난 단계입니다. 경고 하나라도 있으면 동기화를 막습니다.

`Draft`에서 바로 `Final`로 올리지 마세요. 먼저 `Review`로 바꾸고 `Dry Run`을 통과한 뒤, 캐릭터 표정과 모든 선택지 목적지를 확인하고 `Final`로 올립니다.

## 동기화하기

1. Godot 편집기 오른쪽 위 `Notion Dialogue Sync` 패널을 엽니다.
2. 먼저 `Dry Run`을 누릅니다. 이 작업은 게임 파일을 바꾸지 않습니다.
3. 상태, 장면/블록/캐릭터 수, `manifest SHA-256`, 진단 목록을 확인합니다.
4. 오류가 있으면 진단 행을 더블클릭해 Notion 원문을 고친 뒤 다시 `Dry Run`합니다.
5. 이상이 없으면 `Sync Dialogues`를 누릅니다. 성공한 경우에만 `data/generated/dialogues`가 교체됩니다.
6. 동기화 중에는 두 버튼이 잠깁니다. 완료되기 전에 Godot를 닫지 마세요.

게임은 Notion에 접속하지 않고 마지막으로 성공한 로컬 JSON을 읽습니다. 인증 정보가 없어도 플레이할 수 있습니다.

## 진단 메시지 해결표

진단은 `severity [code] message` 형태입니다. 아래 표의 영문은 패널에 표시되는 실제 코드 또는 메시지 핵심 문구입니다.

| code / message | 뜻과 해결 방법 |
|---|---|
| `mapping_error` | Notion 속성이 빠졌거나 형식이 맞지 않습니다. 메시지에 나온 속성의 칸 종류와 값을 확인합니다. |
| `invalid_input` / `must be an array` | 동기화 입력 묶음이 손상되었습니다. 다시 Dry Run하고 계속되면 개발자에게 알립니다. |
| `invalid_scene_key` / `scene_key must be a nonblank string` | 장면의 `scene_key`가 비었습니다. 고유한 영문 키를 적습니다. |
| `duplicate_scene_key` / `scene_key must be unique` | 같은 `scene_key`가 두 장면에 있습니다. 하나를 바꾸고 연결된 블록의 `scene`도 확인합니다. |
| `unsafe_scene_filename` | `manifest`, `CON` 같은 예약 이름이나 `<>:"/\\|?*` 문자를 썼습니다. 점과 영문 소문자 중심의 키로 바꿉니다. |
| `duplicate_scene_filename` | 점이 밑줄로 바뀐 뒤 다른 장면과 파일명이 겹칩니다. 두 `scene_key` 중 하나를 바꿉니다. |
| `invalid_start_flow` / `start_flow must be a nonempty flow name` | 장면의 `start_flow`가 비었습니다. 처음 실행할 흐름 이름을 적습니다. |
| `invalid_flow` / `block flow must be a nonempty name` | 블록의 `flow`가 비었습니다. 같은 묶음에서 사용할 흐름 이름을 적습니다. |
| `unknown_scene` / `block references an unknown scene` | 블록이 삭제되었거나 다른 장면을 가리킵니다. `scene` 관계를 다시 선택합니다. |
| `missing_target_flow` / `a terminal non-end block requires target_flow` | 다음 줄이 없는 블록인데 목적 흐름도 없습니다. `target_flow`를 적거나 마지막 블록을 `end`로 바꿉니다. |
| `unknown_target_flow` / `target_flow does not name a compiled flow` | `target_flow`와 같은 이름의 `flow`가 없습니다. 철자와 공백을 확인합니다. |
| `duplicate_node_id` | 같은 Notion 블록이 중복 수집되었습니다. 복제된 관계/행을 확인하고 개발자에게 알립니다. |
| `unknown_expression` / `expression is not in the character catalog` | 선택한 표정이 캐릭터의 `expressions`에 없습니다. 등록된 표정을 고르거나 새 표정을 요청합니다. |
| `invalid_schema_version` | 생성 형식 버전이 맞지 않습니다. Notion 내용을 더 고치지 말고 개발자에게 알립니다. |
| `invalid_nodes` / `nodes must be a nonempty dictionary` | 장면에 유효한 블록이 하나도 없습니다. 최소 한 줄과 끝 노드를 만듭니다. |
| `invalid_node_id` / `node ids must be nonempty strings` | 블록 식별자가 비정상입니다. 해당 행을 새로 만들거나 개발자에게 알립니다. |
| `invalid_node` / `node must be a dictionary` | 생성된 블록 형식이 손상되었습니다. 개발자에게 알립니다. |
| `invalid_entry_node` / `entry_node must be a nonempty string` | 시작 흐름에 첫 블록이 없습니다. `start_flow` 흐름에 블록을 추가합니다. |
| `missing_entry_node` / `entry_node does not reference a node` | `start_flow`가 실제 블록으로 이어지지 않습니다. 흐름 이름을 맞춥니다. |
| `unsupported_node_type` | `type`이 `line`, `choice`, `effect`, `command`, `jump`, `end` 중 하나가 아닙니다. 올바른 값을 다시 고릅니다. |
| `invalid_field` | 대사/선택지의 필수 값이 비었거나 형식이 틀렸습니다. 뒤의 상세 메시지에서 `speaker`, `text`, `choice item`, `next`, `command` 중 무엇인지 확인합니다. |
| `unknown_character` / `line speaker is not in the character catalog` | `speaker`가 Characters에 없습니다. 관계를 다시 선택하거나 캐릭터 등록을 요청합니다. |
| `invalid_expression` / `line expression must be a nonempty string` | `line`의 표정이 비었습니다. 허용된 표정을 선택합니다. |
| `invalid_condition` | 숨겨진 조건 JSON이 지원 형식이 아닙니다. `notes`에 원하는 조건을 평문으로 남기고 개발자에게 수정 요청합니다. |
| `invalid_effect` | 숨겨진 효과 JSON이 지원 형식이 아닙니다. `notes`에 원하는 효과를 평문으로 남기고 개발자에게 수정 요청합니다. |
| `dangling_target` | 선택지나 다음 노드가 존재하지 않는 블록을 가리킵니다. `target_flow` 철자와 대상 흐름의 첫 행을 확인합니다. |
| `invalid_character_key` / `character keys must be unique and nonempty` | Characters의 `character_key`가 비었거나 중복입니다. 고유한 키로 고칩니다. |
| `cycle_without_exit` / `cycle has no edge to a node outside the cycle` | 분기가 끝없이 반복됩니다. 반복 흐름 바깥으로 나가는 선택지나 `end` 경로를 하나 추가합니다. |
| `automatic_path_too_long` | 대사나 선택지 없이 자동 실행되는 효과/명령/점프가 256개를 넘습니다. 중간에 대사·선택지를 넣거나 흐름을 줄입니다. |

HTTP 401은 토큰 설정, 403/404는 데이터베이스 공유 또는 ID 설정, 429는 잠시 뒤 재시도를 뜻합니다. 이 설정은 개발자 영역이므로 디자이너는 값을 복사해 채팅이나 문서에 붙이지 말고 오류 코드만 전달하세요.
