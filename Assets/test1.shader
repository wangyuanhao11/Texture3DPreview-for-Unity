Shader "Unlit/test1"
{
    Properties
    {
        _MainTex ("Texture", 3D) = "" { }
        _u_size("size",Vector)=(1,1,1,1)
        u_renderthreshold("threshold",float) = 0.5
    }
    SubShader
    {
        Tags
        {
            "Queue" = "Transparent"
        }

        CGINCLUDE
        #include "UnityCG.cginc"

        int _SamplingQuality;
        sampler3D _MainTex;
        float _Density;
        Vector _u_size;
        float u_renderthreshold;

        struct v2f
        {
            float4 pos : SV_POSITION;
            float3 localPos : TEXCOORD0;
            float4 screenPos : TEXCOORD1;
            float3 worldPos : TEXCOORD2;
        };

        v2f vert(appdata_base v)
        {
            v2f OUT;
            OUT.pos = UnityObjectToClipPos(v.vertex);
            OUT.localPos = v.vertex.xyz;
            OUT.screenPos = ComputeScreenPos(OUT.pos);
            COMPUTE_EYEDEPTH(OUT.screenPos.z);
            OUT.worldPos = mul(unity_ObjectToWorld, v.vertex);
            return OUT;
        }

        // usual ray/cube intersection algorithm
        struct Ray
        {
            float3 origin;
            float3 direction;
        };
        bool IntersectBox(Ray ray, out float entryPoint, out float exitPoint)
        {
            float3 invR = 1.0 / ray.direction;
            float3 tbot = invR * (float3(-0.5, -0.5, -0.5) - ray.origin);
            float3 ttop = invR * (float3(0.5, 0.5, 0.5) - ray.origin);
            float3 tmin = min(ttop, tbot);
            float3 tmax = max(ttop, tbot);
            float2 t = max(tmin.xx, tmin.yz);
            entryPoint = max(t.x, t.y);
            t = min(tmax.xx, tmax.yz);
            exitPoint = min(t.x, t.y);
            return entryPoint <= exitPoint;
        }

        float sample1(float3 texcoords) {
            
            return float4(tex3Dlod(_MainTex, float4(texcoords.xyz,0.0f))).r;
            
        }

        float4 add_lighting(float val, float3 loc, float3 step, float3 view_ray){
            const float shininess = 40.0;
            float3 V = normalize(view_ray);
            float3 N;
            float val1, val2;
            val1 = sample1(loc + float3(-step[0], 0.0, 0.0));
            val2 = sample1(loc + float3(+step[0], 0.0, 0.0));
            N[0] = val1 - val2;
            val = max(max(val1, val2), val);
            val1 = sample1(loc + float3(0.0, -step[1], 0.0));
            val2 = sample1(loc + float3(0.0, +step[1], 0.0));
            N[1] = val1 - val2;
            val = max(max(val1, val2), val);
            val1 = sample1(loc + float3(0.0, 0.0, -step[2]));
            val2 = sample1(loc + float3(0.0, 0.0, +step[2]));
            N[2] = val1 - val2;
            val = max(max(val1, val2), val);
            float gm = length(N);
            N = normalize(N);
            
            float Nselect = float(dot(N, V) > 0.0);
            N = (2.0 * Nselect - 1.0) * N;	// ==	Nselect * N - (1.0-Nselect)*N;
            
            float4 ambient_color = float4(0.0, 0.0, 0.0, 0.0);
            float4 diffuse_color = float4(0.0, 0.0, 0.0, 0.0);
            float4 specular_color = float4(0.0, 0.0, 0.0, 0.0);
            for (int i=0; i<1; i++){
                float3 L = normalize(view_ray);	//lightDirs[i];
                float lightEnabled = float( length(L) > 0.0 );
                L = normalize(L + (1.0 - lightEnabled));
                float lambertTerm = clamp(dot(N, L), 0.0, 1.0);
                float3 H = normalize(L+V); // Halfway floattor
                float specularTerm = pow(max(dot(H, N), 0.0), shininess);
                float mask1 = lightEnabled;
                ambient_color +=	mask1 * ambient_color;	// * gl_LightSource[i].ambient;
                diffuse_color +=	mask1 * lambertTerm;
                specular_color += mask1 * specularTerm * specular_color;
                
            }
            
            float4 final_color;
            float4 color = float4(val,val,val,1);
            final_color = color * (ambient_color + diffuse_color) + specular_color;
            final_color.a = color.a;
            return final_color;
            
            
        }
        
        float4 frag(v2f IN) : COLOR
        {
                // _u_size = (1,1,1,1);
                float3 u_size = _u_size.xyz;
                u_renderthreshold = 0.5;
                const int REFINEMENT_STEPS = 4;
                const int MAX_STEPS = 107;
                const float relative_step_size = 0.01;

                float3 localCameraPosition = UNITY_MATRIX_IT_MV[3].xyz;
                float3 v_position = IN.localPos + ( u_size *0.5 );
                float3 view_ray = normalize(IN.localPos.xyz - localCameraPosition.xyz);
            
                float distance = -1000.0;
                distance = max(distance, min(( - v_position.x) / view_ray.x,
                (u_size.x  - v_position.x) / view_ray.x));
                distance = max(distance, min(( - v_position.y) / view_ray.y,
                (u_size.y  - v_position.y) / view_ray.y));
                distance = max(distance, min(( - v_position.z) / view_ray.z,
                (u_size.z  - v_position.z) / view_ray.z));
                float3 front1 = v_position + view_ray * distance;
            
                int nsteps = int((-distance / relative_step_size ));
                if ( nsteps < 1 )
                discard;
                float3 step = ((v_position - front1) / u_size) / float(nsteps);
                float3 start_loc = front1 / u_size;

                // SIO
                float2 u_cw = float2(0,1);
                float3 dstep = relative_step_size/u_size;
                float3 loc = start_loc;
                float low_threshold = (u_renderthreshold - 0.02) * (u_cw.y - u_cw.x);
            
                // [unroll(MAX_STEPS)]
            
                for (int iter=0; iter<MAX_STEPS; ++iter) {
                        if (iter >= nsteps)
                        break; 
                        float val = sample1(loc);
                        if (val > low_threshold && loc.y <0.8 && loc.x >0.2
                        && loc.z >0.2) {
                                float3 iloc = loc - 0.5 * step;
                                float3 istep = step / float(REFINEMENT_STEPS);
                                for (int i=0; i<REFINEMENT_STEPS; i++) {
                                        val = sample1(iloc);
                                        if (val > u_renderthreshold* (u_cw[1] - u_cw[0])) {
                                                return add_lighting(val, iloc, dstep, view_ray);
                                                // return fixed4(val,val,val,1);
                                        }
                                        iloc += istep;
                                }

                                return float4(val,val,val,0.5);
                        }
                        loc += step;
                }

                //////////////////////////////////////////////////////////////////////////



                return float4(0,0,0,1);
        }


        // float4 frag(v2f IN) : COLOR
        // {
            //     // _u_size = (1,1,1,1);
            //     float3 u_size = _u_size.xyz;
            //     u_renderthreshold = 0.5;
            //     const int REFINEMENT_STEPS = 4;
            //     const int MAX_STEPS = 887;
            //     const float relative_step_size = 0.002;

            //     float3 localCameraPosition = UNITY_MATRIX_IT_MV[3].xyz;
            //     float3 v_position = IN.localPos + ( u_size *0.5 );
            //     float3 view_ray = normalize(IN.localPos.xyz - localCameraPosition.xyz);
            
            //     float distance = -1000.0;
            //     distance = max(distance, min(( - v_position.x) / view_ray.x,
            //     (u_size.x  - v_position.x) / view_ray.x));
            //     distance = max(distance, min(( - v_position.y) / view_ray.y,
            //     (u_size.y  - v_position.y) / view_ray.y));
            //     distance = max(distance, min(( - v_position.z) / view_ray.z,
            //     (u_size.z  - v_position.z) / view_ray.z));
            //     float3 front1 = v_position + view_ray * distance;
            
            //     int nsteps = int((-distance / relative_step_size ));
            //     if ( nsteps < 1 )
            //     discard;
            //     float3 step = ((v_position - front1) / u_size) / float(nsteps);
            //     float3 start_loc = front1 / u_size;

            //     // Volume Render
            //     float2 u_cw = float2(0,1);
            //     float3 dstep = relative_step_size/u_size;
            //     float3 loc = start_loc;
            //     float  value=0;
            
            //     // [unroll(MAX_STEPS)]
            
            //     for (int iter=0; iter<MAX_STEPS; ++iter) {
                //         if (iter >= nsteps)
                //         break; 
                //         float val = sample1(loc);
                //         value += val/ nsteps;
                //         loc += step;
            //     }

            //     //////////////////////////////////////////////////////////////////////////



            //     return float4(value,value,value,1);
        // }

        // float4 frag(v2f IN) : COLOR
        // {
        //     // _u_size = (1,1,1,1);
        //     float3 u_size = _u_size.xyz;
        //     u_renderthreshold = 0.5;
        //     const int REFINEMENT_STEPS = 4;
        //     const int MAX_STEPS = 887;
        //     const float relative_step_size = 0.002;

        //     float3 localCameraPosition = UNITY_MATRIX_IT_MV[3].xyz;
        //     float3 v_position = IN.localPos + ( u_size *0.5 );
        //     float3 view_ray = normalize(IN.localPos.xyz - localCameraPosition.xyz);
            
        //     float distance = -1000.0;
        //     distance = max(distance, min(( - v_position.x) / view_ray.x,
        //     (u_size.x  - v_position.x) / view_ray.x));
        //     distance = max(distance, min(( - v_position.y) / view_ray.y,
        //     (u_size.y  - v_position.y) / view_ray.y));
        //     distance = max(distance, min(( - v_position.z) / view_ray.z,
        //     (u_size.z  - v_position.z) / view_ray.z));
        //     float3 front1 = v_position + view_ray * distance;
            
        //     int nsteps = int((-distance / relative_step_size ));
        //     if ( nsteps < 1 )
        //     discard;
        //     float3 step = ((v_position - front1) / u_size) / float(nsteps);
        //     float3 start_loc = front1 / u_size;

        //     // MIP
        //     float2 u_cw = float2(0,1);
        //     float3 dstep = relative_step_size/u_size;
        //     float3 loc = start_loc;
        //     float maxValue=-10000.0;

        //     for (int iter=0; iter<MAX_STEPS; ++iter) {
        //         if (iter >= nsteps)
        //         break; 
        //         float val = sample1(loc);
        //         maxValue = max(maxValue,val);

        //         loc += step;
        //     }

        //     //////////////////////////////////////////////////////////////////////////



        //     return float4(maxValue,maxValue,maxValue,1);
        // }

        ENDCG

        Pass
        {
            Cull front
            Blend One One
            ZWrite false

            CGPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            ENDCG

        }
    }

}
