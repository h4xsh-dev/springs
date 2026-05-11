# Springs

Roblox를 위한 스프링 애니메이션 시스템입니다.
Damped Harmonic Oscillator 수학 연산을 사용합니다.

## 주요 기능

*   **단순화:** `initial`, `target`, `duration`, `bounce` 4가지 파라미터만 사용합니다.
*   **지원 타입:** `number`, `Vector2`, `Vector3`, `UDim`, `UDim2`, `Color3`, `CFrame`와 호환됩니다.

## 4가지 파라미터

1.  **`initial`**: 시작 값
2.  **`target`**: 목표 값
3.  **`duration`**: 스프링이 *안정화*되기까지 걸리는 시간(초)입니다.
4.  **`bounce`**: 스프링이 목표를 얼마나 넘어서는지 결정하는 탄성 수치입니다. 
    *   `0.0`: 튕김 없음
    *   `1.0`: 최대 튕김

## 사용 예제

### 기본 사용법

```lua
local Springs = require(game.ReplicatedStorage.Shared.springs)

local mySpring = Springs.new({
    initial = Vector3.new(0, 0, 0),
    target = Vector3.new(0, 10, 0),
    duration = 1.0,
    bounce = 0.5
})

mySpring:play(workspace.MyPart, "Position")
```

### 타겟 변경

```lua
mySpring:setTarget(Vector3.new(50, 0, 0))
```

### 속성 변경

```lua
mySpring:setDuration(2.0)
mySpring:setBounce(0.0)
```

### 콜백 사용

```lua
mySpring:play(function(value)
    print(value)
end)
```

### 중지

```lua
mySpring:stop()
```

## API 레퍼런스

### `Springs.new(config: SpringConfig) -> Spring`
새로운 스프링 객체를 생성합니다. `initial`과 `target` 값은 반드시 동일한 타입이어야 합니다.

### `Spring:play(instance, property)` / `Spring:play(callback)`
스프링 애니메이션을 자동으로 재생합니다.

### `Spring:stop()`
재생 중인 애니메이션을 중지합니다.

### `Spring:setTarget(newTarget: any)`
목표 값을 변경합니다.

### `Spring:update(deltaTime: number) -> any`
수동으로 스프링을 업데이트합니다. `play()`를 사용하지 않을 때 직접 호출합니다.

### `Spring:setDuration(newDuration: number)`
스프링의 안정화 시간을 변경합니다.

### `Spring:setBounce(newBounce: number)`
튕김 정도를 변경합니다 (0 ~ 1 사이).

### `Spring:getValue() -> any`
시뮬레이션 시간을 진행시키지 않고 현재 계산된 값을 반환합니다.

### `Spring:getVelocity() -> any`
스프링의 현재 속도를 반환합니다.

### `Spring:isSettled() -> boolean`
스프링이 목표에 도달하여 멈췄는지 여부를 반환합니다.

### `Spring:reset(position: any)`
지정된 위치로 스프링을 즉시 이동시키고 속도를 0으로 초기화합니다.
