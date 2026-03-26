import React from "react";
import "./styles/index.scss";
import { Link } from "react-router-dom";
import { NavMenu } from "./navMenu";
import { ButtonToggler } from "./buttonToggler";

export type TopNavBarProps = {
   currentPage?: string;
};

export const TopNavBar: React.FC<TopNavBarProps> = ({ currentPage }) => {
   const [isActive, setActive] = React.useState(0);

   return (
      <header className="navbar-expand-md bg-transparent py-4 fixed-top">
         <div className="container-fluid ms-md-5 ms-3 me-md-5 me-3 pe-5">
            <div className="d-flex justify-content-between align-items-center">
               <Link className={`navbar-brand ${isActive ? "bg-transparent" : "bg-white"}`} to="/">
                  <img src="/uncoverthefuture.svg" width="40" alt="uncoverthefuture" />
               </Link>
               <ButtonToggler state={isActive} action={setActive} />
            </div>
            <NavMenu state={isActive} page={currentPage} />
         </div>
      </header>
   );
};
