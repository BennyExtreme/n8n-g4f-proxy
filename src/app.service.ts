import { Injectable } from '@nestjs/common';
import { HttpService } from '@nestjs/axios';
import { lastValueFrom, map, Observable } from 'rxjs';
import { Readable } from 'stream';

@Injectable()
export class AppService {
  constructor(private readonly http: HttpService) {}

  async getModels(headers: any): Promise<any> {
    const auth: string | null = headers['authorization'];

    const upstream = process.env.LLM_UPSTREAM;
    const provider = process.env.LLM_PROXY_PROVIDER;
    const url = `${upstream}/api/${provider}/models`;

    const resp = await lastValueFrom(
      this.http.get<any>(url, {
        headers: auth ? { Authorization: auth } : {},
      }),
    );

    return resp.data;
  }

  async getProviders(): Promise<string> {
    const upstream = process.env.LLM_UPSTREAM;
    const url = `${upstream}/v1/providers`;

    const response = await lastValueFrom(
      this.http.get<string>(url)
    );
    return response.data;
  }

  postCompletions(body: any, headers: any): Observable<Readable> {
    const auth: string | null = headers['authorization'];

    const upstream = process.env.LLM_UPSTREAM;
    const provider = process.env.LLM_PROXY_PROVIDER;
    const url = `${upstream}/v1/chat/completions`;

    body['provider'] = provider;

    return this.http
      .post(url, body, {
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ...(auth ? { Authorization: auth } : {}),
        },
        responseType: 'stream'
      })
      .pipe(
        map(resp => resp.data as Readable)
      );
  }
}
