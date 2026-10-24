import type { Metadata } from 'next';import './globals.css';
export const metadata:Metadata={title:'DAL · 프로젝트와 대화',description:'프로젝트의 작업물과 대화, 도구 개선 제안을 함께 모으는 비공개 작업실.',icons:{icon:'/favicon.svg'}};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="ko"><body>{children}</body></html>}
