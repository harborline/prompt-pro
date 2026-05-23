import { act } from "react";
import { fireEvent, render, screen } from "@testing-library/react";
import React, { StrictMode, useState } from "react";
import { describe, expect, it, vi } from "vitest";

function Counter({ onIncrement }) {
  const [count, setCount] = useState(0);

  function handleClick() {
    setCount((nextCount) => nextCount + 1);
    onIncrement();
  }

  return (
    <button type="button" onClick={handleClick}>
      Count {count}
    </button>
  );
}

describe("React 19 test patterns", () => {
  it("uses act from react and fireEvent instead of react-dom/test-utils", async () => {
    const onIncrement = vi.fn();

    render(
      <StrictMode>
        <Counter onIncrement={onIncrement} />
      </StrictMode>
    );

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Count 0" }));
    });

    expect(screen.getByRole("button", { name: "Count 1" })).toBeTruthy();
    expect(onIncrement).toHaveBeenCalledTimes(1);
  });
});
