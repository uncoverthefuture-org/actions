import React from "react";

export type ButtonProps = {
   state: number;
   action: any;
};

export const ButtonToggler: React.FunctionComponent<ButtonProps> = ({ state, action }) => {
   const activeState = !state ? "button-toggler" : "button-toggler active";
   return (
      <div
         className={`d-md-none d-block ${activeState}`}
         onClick={() => action(state === 0 ? 1 : 0)}
      >
         <span></span>
         <span></span>
         <span></span>
      </div>
   );
};
