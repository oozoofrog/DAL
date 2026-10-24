import {repository,workspace,bucket,errorResponse} from '../lib/server';import {serveMcp} from '../lib/mcp';
// Sites authorizes the owner-private boundary. Artifact repositories are resolved only for review tools.
export async function POST(request:Request){try{return await serveMcp(request,args=>repository(args.projectId,args.artifactId),bucket(),await workspace())}catch(e){return errorResponse(e)}}
