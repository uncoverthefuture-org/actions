import React from "react";
import "../app.scss";
import "bootstrap/dist/js/bootstrap.bundle.min";
import RootNavigator from "@navigations/routes";
import { ThemeProvider } from "../providers/theme_provider";

const App: React.FC = () => {
   return (
      <ThemeProvider>
         <main>
            <RootNavigator />
         </main>
      </ThemeProvider>
   );
};

export default App;
