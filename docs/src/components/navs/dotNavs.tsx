import React from "react";
import styled from "styled-components";
import "./styles/index.scss";
import "animate.css/animate.min.css";

export type DotProps = {
  slides?: any;
  state?: any;
};

export const DotNavButtons: React.FC<DotProps> = ({ slides, state }) => {
  let indicators: any = (data: any, index: any) =>
    state.default === index + 1
      ? "far fa-asterisk active"
      : "fas fa-circle inactive";

  return (
    <DotButtonsContainer className="d-flex pe-4 pe-lg-5">
      <div className="indicators align-self-center">
        <ul className="list-unstyled pt-5 d-none d-sm-block text-center">
          {slides.map((data: string, index: number) => (
            <li
              className="item-indicator"
              onClick={() => state.action(index + 1)}
            >
              <i className={indicators(index)}></i>
            </li>
          ))}
        </ul>
      </div>
    </DotButtonsContainer>
  );
};

const DotButtonsContainer = styled.div`
  height: 100vh;
  position: fixed;
  text-align: left;
  padding-right: 4rem;
  right: 0;
`;
