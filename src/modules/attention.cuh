#pragma once
#include "modules/param.cuh"
#include "ops/op_elemwise.cuh"
#include "ops/op_reduction.cuh"
#include "ops/op_mm.cuh"
#include "ops/op_softmax.cuh"



template<typename T>
class AttentionLayer {
public:
    int d_model;  // Model dimension [embedding dimension]
    int d_k;      // Dimension of key/query
    int d_v;      // Dimension of value

    Parameter<T> W_q;
    Parameter<T> W_k;
    Parameter<T> W_v;

    AttentionLayer(int d_model_, int d_k_, int d_v_, bool gpu)
        : d_model(d_model_), d_k(d_k_), d_v(d_v_){
        // Initialize weights for query, key, and value projections
        // W_q is of size (d_model, d_k)
        // W_k is of size (d_model, d_k)
        // W_v is of size (d_model, d_v)
        W_q = Parameter<T>{d_model, d_k, gpu};
        W_k = Parameter<T>{d_model, d_k, gpu};
        W_v = Parameter<T>{d_model, d_v, gpu};
    }

    std::vector<Parameter<T>*> parameters() {
        std::vector<Parameter<T> *> v;
        v.push_back(&W_q);
        v.push_back(&W_k);
        v.push_back(&W_v);
        return v;
    }

    void init_uniform() {
        float max = 1.0f / std::sqrt(d_k);
        op_uniform_init(W_q.t, -max, max); 
        op_uniform_init(W_k.t, -max, max); 
        op_uniform_init(W_v.t, -max, max); // do we need to keep values here in that range? 
    }

    void forward(const Tensor<T> &X, Tensor<T> &output) {

        // X is of shape seq_length, d_model
        // W_q, W_k are of shape d_model, d_k and W_v is of shape d_model, d_v 
        Tensor<T> Q(X.h, W_q.t.w, X.on_device); // seq_length, d_k
        Tensor<T> K(X.h, W_k.t.w, X.on_device); // seq_length, d_k
        Tensor<T> V(X.h, W_v.t.w, X.on_device); // seq_length, d_v
        op_mm(X, W_q.t, Q);  // Q = X * W_q 
        op_mm(X, W_k.t, K);  // K = X * W_k
        op_mm(X, W_v.t, V);  // V = X * W_v

        Tensor<T> K_transpose = K.transpose(); // K_transpose is of shape (d_k, seq_length), Q is of shape (seq_length, d_k)
        Tensor<T> QK_T(Q.h, K_transpose.w, Q.on_device); // QK_T is of shape (seq_length, seq_length) 
        op_mm(Q, K_transpose, QK_T); // QK^T 

        Tensor<T> scaled_QK_T(QK_T.h, QK_T.w, QK_T.on_device); // QK_T is of shape (seq_length, seq_length)
        T scale_factor = 1.0 / std::sqrt(d_k);
        // use element-wise multiple of tensor "a" and element b
        op_multiply(QK_T, scale_factor, scaled_QK_T); // Scale QK^T by sqrt(d_k)

        Tensor<T> softmax_QK_T(QK_T.h, QK_T.w, QK_T.on_device);
        op_softmax(scaled_QK_T, softmax_QK_T);  // Apply softmax : QK_T is of shape (seq_length, seq_length)
        op_mm(softmax_QK_T, V, output);  // Output = softmax(QK^T) * V
    }
};
