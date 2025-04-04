`AWS App Mesh`는 애플리케이션의 서비스 간 통신을 쉽게 모니터링하고 제어할 수 있는 서비스 메시입니다.
`서비스 메시`는 네트워크 프록시를 통해 서비스 간의 통신을 처리하는 인프라 계층입니다.

| App Mesh는 서비스 간 통신을 표준화하여 애플리케이션의 가시성과 고가용성을 보장합니다.

`주요 구성 요소`

- 서비스 메시: 서비스 간의 네트워크 트래픽을 관리하는 논리적 경계입니다.
- 가상 서비스: 실제 서비스의 추상화로, 서비스 간 통신을 위한 이름을 제공합니다.
- 가상 노드: 검색 가능한 서비스에 대한 논리 포인터입니다.
- 가상 라우터 및 경로: 트래픽을 처리하고 특정 기준에 따라 트래픽을 라우팅합니다.
- 프록시: App Mesh 구성을 읽고 트래픽을 적절하게 전달합니다.

`예제`

기존 애플리케이션에서 serviceA가 serviceB와 통신한다고 가정합니다. serviceB의 새 버전 serviceBv2를 배포하고, serviceA의 트래픽을 두 서비스로 나누어 보내고 싶다면, App Mesh를 사용하면 애플리케이션 코드를 변경하지 않고도 이를 쉽게 설정할 수 있습니다.

App Mesh를 사용하면 서비스 간 통신이 프록시를 통해 이루어지며, 프록시는 App Mesh 구성을 읽고 트래픽을 적절하게 라우팅합니다. 이를 통해 서비스 간 통신 방식을 유연하게 제어할 수 있습니다.

- 가상 서비스: 여러 가상 노드를 하나의 서비스로 묶는 추상화.
- 가상 노드: 실제 서비스 인스턴스를 나타내는 논리 포인터.
- 가상 라우터: 트래픽을 여러 가상 노드로 분배하는 역할.
