import introDoc from "./intro.md?raw";
import buildDoc from "./build_and_push.md?raw";
import deployDoc from "./ssh_container_deploy.md?raw";

export const UI_CONFIG = {
  sidebarFrameUrl: "frames/sidebar",
  docContentFrameUrl: "frames/doc_content",
  defaultTheme: "dark" as "light" | "dark",
};

export interface NavItem {
    label: string;
    route?: string;
    children?: NavItem[];
}

export const navItems: NavItem[] = [
    {
        label: "Introduction",
        route: "/"
    },
    {
        label: "Build Dispatch",
        children: [
            {
                label: "Build & Push",
                route: "/actions/build-and-push",
            },
        ],
    },
    {
        label: "App Dispatch",
        children: [
            {
                label: "SSH Container Deploy",
                route: "/actions/ssh-container-deploy",
            },
        ],
    },
];

export const titleMap: Record<string, string> = {
    "/": "Uncover Actions",
    "/actions/build-and-push": "Build & Push Action",
    "/actions/ssh-container-deploy": "SSH Deploy Action",
};

export const contentMap: Record<string, string> = {
    "/": introDoc,
    "/actions/build-and-push": buildDoc,
    "/actions/ssh-container-deploy": deployDoc,
};
