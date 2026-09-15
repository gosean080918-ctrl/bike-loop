안녕하세요. 방치 자전거의 수거 대상과 차량 이동 경로를 최적화하기 위한 Python 예제 코드를 공유드립니다.

이 코드는 신고된 자전거를 위치에 따라 hotspot으로 묶은 뒤, 신고 경과일, 자전거 수, 이동거리, 차량 적재량 등을 함께 고려하여 수거할 자전거와 방문 순서를 결정하는 구조입니다.

전체적인 로직은 다음과 같습니다.

1. 30m 기준 Hotspot 생성

* 신고 위치가 가까운 자전거들을 반경 30m의 cluster로 구성합니다.
* 각 cluster의 모든 자전거가 대표 지점(anchor bike)으로부터 30m 이내에 있도록 하여, 연결된 자전거를 따라 cluster가 지나치게 커지는 chaining 문제를 방지했습니다.
* 고립된 자전거도 size가 1인 cluster로 처리합니다.
* 중복 신고 여부는 실제로 검증하기 어렵기 때문에 별도의 중복 탐지 기능은 포함하지 않았으며, 각 신고를 독립된 자전거 1대로 취급합니다.

2. Cluster 정보 계산

각 cluster에 대해 다음 정보를 계산합니다.

* 가장 오래된 신고의 경과일
* 오래된 상위 3대의 평균 경과일
* cluster 내 전체 자전거 수
* 60일 이상 경과한 자전거 수
* 90일 이상 경과한 자전거 수
* 예상 수거 시간
* Start와 Storage를 기준으로 한 추가 이동거리
* 실제 cluster 반경

신고 경과일은 다음과 같은 urgency tier로 구분했습니다.

* Critical: 90일 이상
* High: 60~89일
* Medium: 30~59일
* Normal: 30일 미만

3. 개별 자전거 Priority 계산

각 자전거에는 신고 경과일과 urgency tier를 바탕으로 priority point를 부여합니다.

데이터가 제공되는 경우 위험도(`hazard_score`)와 현장 존재 가능성(`confidence`)도 반영할 수 있도록 구성했으며, 해당 데이터가 없으면 기본값을 사용합니다.

한 cluster에서 일부 자전거만 수거해야 하는 경우에는 priority가 높은 자전거, 즉 기본적으로 신고가 오래된 자전거부터 선택합니다.

4. Cluster별 수거 대안 생성

각 cluster에 대해 다음과 같은 수거 대안을 생성합니다.

* 해당 cluster를 방문하지 않음
* 가장 오래된 자전거 1대 수거
* 가장 오래된 자전거 2대 수거
* …
* cluster 전체 수거

Cluster 전체를 수거하는 대안에는 completion bonus를 추가하여, 가능하면 방문한 cluster를 완전히 처리하도록 유도했습니다.

다만 전체 수거를 강제하지는 않으므로, 차량 적재량이나 다른 cluster의 priority를 고려했을 때 필요한 경우 일부 자전거만 수거할 수 있습니다.

5. OR-Tools를 이용한 통합 최적화

OR-Tools가 다음 사항을 동시에 결정합니다.

* 방문할 cluster
* 각 cluster에서 수거할 자전거 수
* Start → 선택된 clusters → Storage의 방문 순서

목적함수에는 다음 요소가 반영됩니다.

* 차량 이동거리
* 현장 수거 시간에 해당하는 비용
* 수거하지 못한 자전거의 priority penalty

다음과 같은 제약조건도 포함되어 있습니다.

* 차량 최대 적재량
* 최대 운행시간
* 한 cluster에서는 하나의 수거량 대안만 선택
* 출발지는 Start, 최종 도착지는 Storage

6. 결과 출력 및 시각화

실행 결과에는 다음 정보가 출력됩니다.

* 전체 cluster의 priority 정보
* 실제 선택된 cluster와 자전거
* cluster별 전체 또는 부분 수거 여부
* 최적 방문 순서
* 총 수거량과 남은 적재량
* 총 이동거리
* 예상 운행 및 수거 시간
* 획득한 총 priority

지도에는 모든 자전거의 위치를 표시하되, 개별 자전거마다 설명을 표시하지 않고 실제 방문하는 cluster에 대해서만 수거 대수, 자전거 코드, urgency tier, 신고 경과일 등의 요약 정보를 표시합니다.

주요 조정 가능 파라미터는 다음과 같습니다.

* `cluster_radius_m`: hotspot 반경
* `vehicle_capacity`: 차량 최대 적재량
* `completion_bonus_ratio`: cluster 전체 수거에 대한 bonus
* `max_route_minutes`: 최대 운행시간
* `average_speed_kmh`: 평균 차량 속도
* `priority_value_m_per_point`: 신고 priority와 이동거리 사이의 가중치
* `service_cost_m_per_minute`: 현장 수거 시간의 비용
* `pickup_minutes`: 자전거 1대당 예상 수거 시간

현재 예제에서는 좌표 간 직선거리인 Haversine distance를 사용합니다. 실제 앱에 적용할 때는 차량 이동거리와 시간을 정확하게 반영하기 위해 이 부분을 Kakao Mobility 등의 도로 거리 및 소요시간 matrix로 교체하면 됩니다.
