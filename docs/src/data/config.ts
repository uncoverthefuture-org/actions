import sshContainerDeploy from "./ssh_container_deploy.md?raw";

export const UI_CONFIG = {
  sidebarFrameUrl: `${import.meta.env.BASE_URL}frames/sidebar`,
  docContentFrameUrl: `${import.meta.env.BASE_URL}frames/doc_content`,
};

export interface NavItem {
    label: string;
    route?: string;
    children?: NavItem[];
}

export const navItems: NavItem[] = [
    {
        label: "Home",
        route: "/"
    },
    {
        label: "Packages",
        children: [
            {
                label: "@uncover/actions",
                children: [
                    {
                        label: "SSH Container Deploy",
                        route: "/uncover-actions/ssh-container-deploy",
                    },
                ],
            },
        ],
    },
];

export const titleMap: Record<string, string> = {
    "/": "Documentation",
    "/uncover-actions/ssh-container-deploy": "SSH Container Deploy",
};

export const contentMap: Record<string, string> = {
    "/": "# Welcome to Uncover Actions Docs \n Select a function from the sidebar to view usage details.",
    "/uncover-actions/ssh-container-deploy": sshContainerDeploy,
};
