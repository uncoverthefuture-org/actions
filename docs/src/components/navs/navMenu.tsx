import React from "react";
import "animate.css/animate.min.css";
import { Link } from "react-router-dom";
import styled from "styled-components";

export type NavProps = {
   page: any;
   state: number;
};

export const NavMenu: React.FunctionComponent<NavProps> = ({ page, state }) => {
   const active = (url: string) => page === url && "active";

   return (
      <NavContainer className={`nav-menu ${!state ? "d-none" : "d-block"}`}>
         <div className="d-flex h-75 align-items-center justify-content-end ps-0" id="navbarNav">
            <ul className="navbar-nav list-unstyled ps-2 ps-md-5">
               <li className="nav-item">
                  <Link className={`nav-link ${active("home")}`} to="/">
                     Home
                  </Link>
               </li>

               <li className="nav-item">
                  <Link className={`nav-link ${active("dream")}`} to="/dream">
                     Our Dream
                  </Link>
               </li>

               <li className="nav-item">
                  <Link className={`nav-link ${active("ideas")}`} to="/ideas">
                     Our Ideas
                  </Link>
               </li>

               <li className="nav-item">
                  <Link className={`nav-link ${active("contact")}`} to="/contact">
                     Contact Us
                  </Link>
               </li>
            </ul>
         </div>
         <div className="container d-md-none d-block border-top fixed-bottom py-3">
            <div className="d-flex justify-content-between align-items-center">
               <span className="d-block">© {new Date().getFullYear()} Uncoverthefuture</span>
               <span className="d-block">Terms and conditions</span>
            </div>
         </div>
      </NavContainer>
   );
};

const NavContainer = styled.nav`
   top: 0;
   right: 0;
   left: 0;
   width: 100%;
   height: 100vh;
   z-index: -50;
   background: #eaf0f1;
   position: fixed;
`;
